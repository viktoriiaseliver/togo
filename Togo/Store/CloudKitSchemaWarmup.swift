#if DEBUG
import Foundation
import SwiftData

/// Прогрев зеркала CloudKit. Отладочная сборка, живой Apple ID, один раз.
///
/// Зачем это вообще есть. Типы `CD_*` в CloudKit заводит не файл схемы
/// и не человек, а само зеркало SwiftData — при первой записи объекта
/// этого типа, и только в среде development. Пока ни один `Trip`
/// не сохранялся на сборке с iCloud, типа `CD_Trip` в контейнере нет,
/// а в production он не появится никогда: там схему только переносят
/// кнопкой из development.
///
/// Замер 23.09: из шестнадцати моделей зеркалились пять. Прогулки, дозы,
/// занятия, поездки и документы не уезжали в iCloud ни у кого, а политика
/// обещала «копия базы лежит в твоей приватной библиотеке iCloud».
///
/// **Замер 14.10, и он больше первого: не заведено 83 поля.** Шестьдесят
/// из них — пять типов медслоя (`Clinic`, `LabResult`, `VetVisit`,
/// `Diagnosis`, `Prescription`) целиком: моделей стало 21, а этот список
/// объектов остался на шестнадцати. То есть **вся медкнижка не имела
/// резервной копии в iCloud вообще**, а политика обещала то же самое.
///
/// Два раза подряд одно и то же, и причина одна: **список объектов
/// здесь — рукописная копия набора моделей.** Он не ломается и не
/// краснеет, он просто отстаёт, и отставание видно только снаружи.
/// Сторож (`make cloudkit-check`) с 14.10 берёт ось от схемы приложения
/// и назовёт следующую пропажу по имени — но завести объект всё равно
/// придётся сюда, рукой.
///
/// Порядок работы:
/// 1. Отладочная сборка на устройстве с живым Apple ID, iCloud включён.
/// 2. «Настройки» → «Отладка · завести зеркало в iCloud».
/// 3. Подождать минуту при живой сети — зеркало отправит записи.
/// 4. `make cloudkit-check` — он скажет, каких типов и полей ещё нет.
/// 5. «Отладка · убрать прогрев», когда сверка зелёная.
///
///    **Числа здесь нет нарочно.** Прежде стояло «когда все шестнадцать
///    на месте» — к 14.10.2026 моделей стало 21, и инструкция звала
///    остановиться на пяти типах раньше, чем надо. Порог, записанный
///    числом, переживает тот набор, про который написан; порог,
///    записанный как «сверка зелёная», — нет.
/// 6. Перенос development → production — кнопкой в дашборде.
nonisolated enum CloudKitSchemaWarmup {

    /// Метка прогрева: 1 января 2001 года. Настоящей записи с такой датой
    /// быть не может, и удаление потом попадает ровно в свои объекты,
    /// а не в чужой дневник.
    static let markerDate = Date(timeIntervalSinceReferenceDate: 0)

    /// Метка для того, у чего есть название.
    static let markerTitle = "ПРОГРЕВ СХЕМЫ"

    /// Идентификаторы созданного. Метка в поле — не опора: `LogEvent`
    /// и `DoseRecord` ездят в общий дневник, и слияние переписывает им
    /// `authorName` и `scheduledAt` из приехавшего payload
    /// (`SharedDiaryPayloads:40` и `:81`). Замер 23.09: после «убрать
    /// прогрев» остались ровно эти два типа — те самые, что
    /// синхронизируются. Идентификатор не переписывает никто.
    private static let ключИдентификаторов = "debug.warmup.ids"

    /// Записи раньше 2002 года в дневнике собаки быть не может: приложению
    /// меньше года. Это вторая сеть — для тех двух типов, что ездят
    /// в общий дневник и возвращаются из облака с переписанными полями,
    /// и для объектов, заведённых прошлой сборкой, чьих идентификаторов
    /// мы не сохранили.
    static let доПрограммы = Date(timeIntervalSinceReferenceDate: 365 * 24 * 3600)

    private static var сохранённыеИдентификаторы: Set<UUID> {
        get {
            let строки = UserDefaults.standard.stringArray(forKey: ключИдентификаторов) ?? []
            return Set(строки.compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: ключИдентификаторов)
        }
    }

    /// Завести по одному объекту каждого типа, которого зеркало ещё
    /// не видело, и по одному объекту типов, у которых не хватает полей.
    /// Возвращает, сколько объектов создано.
    ///
    /// Про поля пришлось дописывать отдельно, и это была моя ошибка
    /// в первой редакции: зеркало заводит поле при первой записи
    /// СО ЗНАЧЕНИЕМ, поэтому мало создать объект — надо заполнить
    /// у него всё, что бывает пустым. Замер 23.09 после первого прогрева:
    /// у `CD_Dog` не хватало десяти полей (номер чипа, телефон врача,
    /// целевой вес), у `CD_LogEvent` пяти, у `CD_FamilyMember` пяти.
    @MainActor
    @discardableResult
    static func create(in context: ModelContext) throws -> Int {
        // Клиника заводится первой: на неё ссылаются уход, приём врача
        // и назначение, а связь в зеркале становится полем только когда
        // ей есть на что указывать.
        let клиника = клиникаСоВсемиПолями()
        // Собака — по той же причине, что клиника, и это замер 20.10.2026:
        // у `CD_Diagnosis`, `CD_LabResult`, `CD_Prescription` и `CD_VetVisit`
        // поля `dog` не было в контейнере именно потому, что `.dog`
        // не присваивался ни одному объекту прогрева — связь в зеркале
        // становится полем только когда ей есть на что указывать.
        // Без этой строки один прогрев заводил 79 полей из 83, и за
        // оставшимися четырьмя пришлось бы идти вторым заходом.
        let собака = собакаСоВсемиПолями()

        let objects: [any PersistentModel] = [
            DayOut(startedAt: markerDate, plannedHours: 1),
            дозаСоВсемиПолями(),
            Episode(title: markerTitle, detail: markerTitle, startedAt: markerDate),
            HeatRecord(startedAt: markerDate, note: markerTitle),
            ProcedureSkill(title: markerTitle, detail: markerTitle),
            TrainingSession(cue: markerTitle, place: markerTitle, person: markerTitle,
                            distanceMeters: 0),
            TrainingStep(cue: markerTitle, place: markerTitle, person: markerTitle,
                         distanceMeters: 0),
            Trip(destination: markerTitle, startDate: markerDate, endDate: markerDate,
                 transport: .car),
            клиника,
            собака,
            участникСоВсемиПолями(),
            записьСоВсемиПолями(),
            лекарствоСоВсемиПолями(),
            документСоВсемиПолями(),
            уходСоВсемиПолями(клиника),
            запасСоВсемиПолями(),
            взвешиваниеСоВсемиПолями(),
            анализСоВсемиПолями(собака),
            приёмВрачаСоВсемиПолями(клиника, собака),
            диагнозСоВсемиПолями(собака),
            назначениеСоВсемиПолями(клиника, собака),
        ]
        for object in objects { context.insert(object) }
        сохранённыеИдентификаторы = сохранённыеИдентификаторы.union(objects.compactMap(идентификатор))
        // Сохранение здесь не молчит: прогрев ради того и делается, чтобы
        // записи ушли в зеркало. Не сохранилось — человек должен узнать
        // сразу, а не по пустой схеме через час.
        try context.save()
        return objects.count
    }

    /// Собака со всеми необязательными полями: иначе номер чипа,
    /// телефон врача и целевой вес в iCloud не заведутся никогда.
    @MainActor
    private static func собакаСоВсемиПолями() -> Dog {
        let собака = Dog(name: markerTitle, weightKg: 1)
        собака.birthDate = markerDate
        собака.chipNumber = markerTitle
        собака.passportNumber = markerTitle
        собака.insuranceNumber = markerTitle
        собака.vetName = markerTitle
        собака.vetPhone = markerTitle
        собака.clinicName = markerTitle
        собака.clinicPhone = markerTitle
        собака.distinctiveMarks = markerTitle
        собака.targetWeightLow = 1
        собака.targetWeightHigh = 2
        собака.deletedAt = markerDate
        return собака
    }

    @MainActor
    private static func участникСоВсемиПолями() -> FamilyMember {
        let участник = FamilyMember(name: markerTitle, role: .observer)
        участник.note = markerTitle
        участник.customPermissionsRaw = [Permission.seeMedical.rawValue]
        участник.dutyUntil = markerDate
        участник.acceptedAt = markerDate
        участник.accessExpiresAt = markerDate
        return участник
    }

    @MainActor
    private static func записьСоВсемиПолями() -> LogEvent {
        let запись = LogEvent(kind: .note, date: markerDate, authorName: markerTitle)
        запись.enteredAt = markerDate
        запись.incidentDetailRaw = markerTitle
        запись.milliliters = 1
        запись.originRaw = markerTitle
        запись.trainingSessionID = UUID()
        запись.editedBy = markerTitle
        return запись
    }

    // MARK: Дописано 14.10.2026 — пять типов и восемнадцать полей
    //
    // **Замер, с которого это началось: не заведено 83 поля, а не 23.**
    // Прежний отчёт сторожа зеркала считал цикл по типам, найденным
    // в выгрузке, — значит о типе, которого нет вовсе, не говорил ничего.
    // Пяти моделей медслоя (`Clinic`, `LabResult`, `VetVisit`,
    // `Diagnosis`, `Prescription`) в зеркале не было, и это 60 полей
    // из 83: вся медкнижка без резервной копии в iCloud, а не «частично».
    //
    // Почему их тут не было раньше: модели завели 07.10.2026, а прогрев
    // писался 23.09 под шестнадцать моделей. Список объектов — **копия
    // набора моделей, сделанная руками**, и она отстала ровно так же,
    // как отстал `schema.ckdb` у общего дневника. Сторож теперь берёт
    // ось от схемы приложения и назовёт любую следующую пропажу.
    //
    // `CareTask` и `WeightEntry` в списке не было вовсе — их типы
    // завелись не прогревом, а посевом, и потому выглядели здоровыми.
    //
    // **Куда это пишется.** Вывод верный: прогрев физически не может
    // положить запись туда, где второй человек. Но держится он
    // не на том, на чём здесь было написано.
    //
    // Было: «`Debug.xcconfig:7` — `APS_ENVIRONMENT = development`,
    // `Release.xcconfig:11` — `production`». Замер 14.10.2026:
    // `APS_ENVIRONMENT` подставляется в `aps-environment`
    // (`Togo.entitlements:26`) и управляет **пушами**, а не базой
    // CloudKit. Среду контейнера задаёт
    // `com.apple.developer.icloud-container-environment`, и его
    // в `Configuration/*.entitlements` **нет ни одного** — значит его
    // подставляет Xcode по типу сборки.
    //
    // > **Объяснение, придуманное к верному замеру, наследует его
    // > достоверность и не имеет своей.** Вывод был прав, довод —
    // > про соседний механизм, и проверить его никто не ходил
    // > именно потому, что вывод сходился.
    //
    // Довод, который НЕ зависит от среды вовсе и потому главный:
    // **весь этот файл под `#if DEBUG`** — в сборке Release кода
    // прогрева нет вовсе, а TestFlight это Release. Сборка, которая
    // у второго человека, создать такую запись не может, даже если
    // про среды мы ошиблись.
    //
    // Второй довод, уже про среды: отладочная сборка с кабеля ходит
    // в Development, TestFlight — в Production, это разные базы.
    // Он верен, но проверяется не здесь, а в правах сборки.
    //
    // Проверять это надо **до** запуска, а не после, и потому замер
    // записан здесь, а не в журнале.

    /// Клиника: на неё ссылаются уход, приём врача и назначение.
    @MainActor
    private static func клиникаСоВсемиПолями() -> Clinic {
        let клиника = Clinic(name: markerTitle, detail: markerTitle,
                             isLab: true, phone: markerTitle)
        клиника.deletedAt = markerDate
        return клиника
    }

    /// Лекарство со всем слоем запаса и сроков: одиннадцать полей
    /// из двадцати трёх недостающих — здесь.
    @MainActor
    private static func лекарствоСоВсемиПолями() -> Medication {
        let лекарство = Medication(name: markerTitle, doseText: markerTitle, times: [0])
        лекарство.unitRaw = MedUnit.tab.rawValue
        лекарство.massPerUnitMcg = 1
        лекарство.stockLeftAmount = 1
        лекарство.packAmount = 1
        лекарство.courseEnd = markerDate
        лекарство.expiry = markerDate
        лекарство.openedAt = markerDate
        лекарство.shelfAfterOpenDays = 1
        лекарство.remindBeforeExpiry = true
        лекарство.canGiveOutside = true
        лекарство.prescriptionNumber = markerTitle
        лекарство.deletedAt = markerDate
        return лекарство
    }

    @MainActor
    private static func документСоВсемиПолями() -> DogDocument {
        let документ = DogDocument(title: markerTitle, note: markerTitle)
        документ.kindRaw = DocumentKind.other.rawValue
        документ.number = markerTitle
        документ.issuedBy = markerTitle
        документ.validUntil = markerDate
        документ.deletedAt = markerDate
        return документ
    }

    /// Уход с прививочными полями и связью на клинику.
    @MainActor
    private static func уходСоВсемиПолями(_ клиника: Clinic) -> CareTask {
        let уход = CareTask(title: markerTitle, detail: markerTitle,
                            lastDone: markerDate, scheduledDate: markerDate)
        уход.vaccineBatch = markerTitle
        уход.vaccineValidUntil = markerDate
        уход.clinic = клиника
        уход.deletedAt = markerDate
        return уход
    }

    @MainActor
    private static func запасСоВсемиПолями() -> FoodStock {
        let запас = FoodStock(kind: .dry, brand: markerTitle, packGrams: 1,
                              packsLeft: 1, gramsPerDay: 1, countedAt: markerDate)
        запас.openedAt = markerDate
        запас.expiry = markerDate
        запас.shelfAfterOpenDays = 1
        return запас
    }

    @MainActor
    private static func взвешиваниеСоВсемиПолями() -> WeightEntry {
        let взвешивание = WeightEntry(date: markerDate, kg: 1)
        взвешивание.deletedAt = markerDate
        return взвешивание
    }

    /// Отметка приёма. Нужна прогреву **только ради надгробия**
    /// (26.10.2026): остальные её поля в зеркале уже есть, а `deletedAt`
    /// заводится записью со значением и только в development.
    ///
    /// Прежде доза заводилась строкой `DoseRecord(scheduledAt:)` прямо
    /// в списке объектов, и дописать ей поле было негде.
    @MainActor
    private static func дозаСоВсемиПолями() -> DoseRecord {
        let доза = DoseRecord(scheduledAt: markerDate)
        доза.deletedAt = markerDate
        return доза
    }

    /// Анализ. `labMark` и `method` заполняются здесь **меткой прогрева**,
    /// а не правдоподобным значением, и это не мелочь: у обоих полей
    /// есть красная линия показа (`Togo/CLAUDE.md`) — вердикт рядом
    /// с подписью «кто сказал», и запрет рисовать одной линией значения,
    /// снятые разными методами. Объект живёт до «убрать прогрев»
    /// и в показ не попадает, но значение, похожее на настоящее,
    /// однажды попало бы.
    @MainActor
    private static func анализСоВсемиПолями(_ собака: Dog) -> LabResult {
        let анализ = LabResult(sampledOn: markerDate, indicator: markerTitle,
                               section: markerTitle, laboratory: markerTitle,
                               reportNumber: markerTitle)
        анализ.sampledAt = markerDate
        анализ.value = 1
        анализ.belowLimit = 1
        анализ.aboveLimit = 1
        анализ.textValue = markerTitle
        анализ.unit = markerTitle
        анализ.referenceLow = 1
        анализ.referenceHigh = 2
        анализ.method = markerTitle
        анализ.labMark = markerTitle
        анализ.note = markerTitle
        анализ.dog = собака
        анализ.deletedAt = markerDate
        return анализ
    }

    @MainActor
    private static func приёмВрачаСоВсемиПолями(_ клиника: Clinic, _ собака: Dog) -> VetVisit {
        let приём = VetVisit(date: markerDate, doctor: markerTitle,
                             reasonRaw: VisitReason.checkup.rawValue)
        приём.clinic = клиника
        приём.conclusion = markerTitle
        приём.dog = собака
        приём.deletedAt = markerDate
        return приём
    }

    @MainActor
    private static func диагнозСоВсемиПолями(_ собака: Dog) -> Diagnosis {
        let диагноз = Diagnosis(wording: markerTitle, madeOn: markerDate,
                                statusRaw: DiagnosisStatus.hypothesis.rawValue)
        диагноз.madeBy = markerTitle
        диагноз.evidence = markerTitle
        диагноз.dog = собака
        диагноз.deletedAt = markerDate
        return диагноз
    }

    @MainActor
    private static func назначениеСоВсемиПолями(_ клиника: Clinic, _ собака: Dog) -> Prescription {
        let назначение = Prescription(number: markerTitle, date: markerDate,
                                      medicationName: markerTitle)
        назначение.clinic = клиника
        назначение.doctor = markerTitle
        назначение.dogWeightKg = 1
        назначение.dosage = markerTitle
        назначение.schedule = markerTitle
        назначение.duration = markerTitle
        назначение.pharmacyForm = markerTitle
        назначение.controlFromWeeks = 1
        назначение.controlToWeeks = 2
        назначение.dispensed = markerTitle
        назначение.instruction = markerTitle
        назначение.source = markerTitle
        назначение.dog = собака
        назначение.deletedAt = markerDate
        return назначение
    }

    /// Убрать прогрев. Тип в схеме остаётся — он и был целью; уходят
    /// только объекты. Возвращает, сколько удалено.
    @MainActor
    @discardableResult
    static func remove(in context: ModelContext) throws -> Int {
        var removed = 0
        let свои = сохранённыеИдентификаторы
        removed += delete(DayOut.self, in: context) { $0.startedAt == markerDate || свои.contains($0.id) }
        removed += delete(DogDocument.self, in: context) { $0.title == markerTitle || свои.contains($0.id) }
        removed += delete(DoseRecord.self, in: context) {
            $0.scheduledAt < доПрограммы || свои.contains($0.id)
        }
        removed += delete(Episode.self, in: context) { $0.title == markerTitle || свои.contains($0.id) }
        removed += delete(FoodStock.self, in: context) { $0.brand == markerTitle || свои.contains($0.id) }
        removed += delete(HeatRecord.self, in: context) { $0.startedAt == markerDate || свои.contains($0.id) }
        removed += delete(Medication.self, in: context) { $0.name == markerTitle || свои.contains($0.id) }
        removed += delete(ProcedureSkill.self, in: context) { $0.title == markerTitle || свои.contains($0.id) }
        removed += delete(TrainingSession.self, in: context) { $0.cue == markerTitle || свои.contains($0.id) }
        removed += delete(TrainingStep.self, in: context) { $0.cue == markerTitle || свои.contains($0.id) }
        removed += delete(Trip.self, in: context) { $0.destination == markerTitle || свои.contains($0.id) }
        removed += delete(Dog.self, in: context) { $0.name == markerTitle || свои.contains($0.id) }
        removed += delete(FamilyMember.self, in: context) { $0.name == markerTitle || свои.contains($0.id) }
        removed += delete(LogEvent.self, in: context) {
            $0.authorName == markerTitle || $0.date < доПрограммы || свои.contains($0.id)
        }
        // Дописано 14.10.2026 вместе с созданием этих семи.
        //
        // **Создание и удаление правятся ОДНОЙ правкой, и это не стиль.**
        // Заведи объект без своей строки здесь — и «убрать прогрев»
        // скажет «удалено N», оставив его в хранилище. Число на экране
        // при этом не соврёт: оно считает удалённое, а не оставшееся.
        // Ловит это `остатки(in:)`, но только если и он знает про тип, —
        // поэтому третья правка в `остатки` идёт той же рукой.
        removed += delete(CareTask.self, in: context) { $0.title == markerTitle || свои.contains($0.id) }
        removed += delete(WeightEntry.self, in: context) { $0.date < доПрограммы || свои.contains($0.id) }
        removed += delete(Clinic.self, in: context) { $0.name == markerTitle || свои.contains($0.id) }
        removed += delete(LabResult.self, in: context) { $0.laboratory == markerTitle || свои.contains($0.id) }
        removed += delete(VetVisit.self, in: context) { $0.doctor == markerTitle || свои.contains($0.id) }
        removed += delete(Diagnosis.self, in: context) { $0.wording == markerTitle || свои.contains($0.id) }
        removed += delete(Prescription.self, in: context) { $0.number == markerTitle || свои.contains($0.id) }
        try context.save()
        // Список чистим только когда чистить больше нечего: иначе
        // второе нажатие потеряет опору и промахнётся так же, как
        // промахнулись метки в полях.
        if остатки(in: context).isEmpty { сохранённыеИдентификаторы = [] }
        return removed
    }

    /// Сколько служебных записей прогрева осталось в хранилище.
    ///
    /// Нужно затем, что «вроде бы всё ушло» — не замер. Кнопка «убрать
    /// прогрев» может сказать «удалено 14» и всё равно оставить объект,
    /// который не попал в выборку: предикат у каждого типа свой, и
    /// ошибиться в одном из четырнадцати легко. Число на экране — это
    /// проверка того, что сделала кнопка, а не доверие к ней.
    @MainActor
    static func сколькоОсталось(in context: ModelContext) -> Int {
        остатки(in: context).values.reduce(0, +)
    }

    /// Что именно осталось, по типам. Число без имени типа не чинится:
    /// предикат удаления у каждого свой, и знать надо, который промахнулся.
    /// Что лежит у каждой собаки. Нужно затем, что удаление собаки
    /// уносит каскадом всё: записи, вес, уход, препараты, занятия,
    /// поездки. Прежде чем трогать дубликат, надо знать, у какой
    /// из них данные, — а не гадать по кличке.
    @MainActor
    static func собаки(in context: ModelContext) -> String {
        let все = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        guard !все.isEmpty else { return "собак нет" }
        let формат = Date.FormatStyle(date: .numeric, time: .shortened)
        return все.map { собака in
            let записей = собака.eventsStorage?.count ?? 0
            let вес = собака.weightsStorage?.count ?? 0
            let уход = собака.careTasksStorage?.count ?? 0
            let препараты = собака.medicationsStorage?.count ?? 0
            return "«\(собака.name)» заведена \(собака.createdAt.formatted(формат)): "
                + "записей \(записей), взвешиваний \(вес), дел ухода \(уход), препаратов \(препараты)"
        }.joined(separator: "\n")
    }

    /// Идентификатор объекта прогрева, если он у типа есть.
    private static func идентификатор(_ объект: any PersistentModel) -> UUID? {
        switch объект {
        case let x as DayOut: x.id
        case let x as DogDocument: x.id
        case let x as DoseRecord: x.id
        case let x as Episode: x.id
        case let x as FoodStock: x.id
        case let x as HeatRecord: x.id
        case let x as Medication: x.id
        case let x as ProcedureSkill: x.id
        case let x as TrainingSession: x.id
        case let x as TrainingStep: x.id
        case let x as Trip: x.id
        case let x as Dog: x.id
        case let x as FamilyMember: x.id
        case let x as LogEvent: x.id
        default: nil
        }
    }

    @MainActor
    static func остатки(in context: ModelContext) -> [String: Int] {
        var найдено: [String: Int] = [:]
        let свои = сохранённыеИдентификаторы
        func учесть(_ имя: String, _ сколько: Int) {
            if сколько > 0 { найдено[имя] = сколько }
        }
        учесть("DayOut", count(DayOut.self, in: context) { $0.startedAt == markerDate || свои.contains($0.id) })
        учесть("DogDocument", count(DogDocument.self, in: context) { $0.title == markerTitle || свои.contains($0.id) })
        учесть("DoseRecord", count(DoseRecord.self, in: context) {
            $0.scheduledAt < доПрограммы || свои.contains($0.id)
        })
        учесть("Episode", count(Episode.self, in: context) { $0.title == markerTitle || свои.contains($0.id) })
        учесть("FoodStock", count(FoodStock.self, in: context) { $0.brand == markerTitle || свои.contains($0.id) })
        учесть("HeatRecord", count(HeatRecord.self, in: context) { $0.startedAt == markerDate || свои.contains($0.id) })
        учесть("Medication", count(Medication.self, in: context) { $0.name == markerTitle || свои.contains($0.id) })
        учесть("ProcedureSkill", count(ProcedureSkill.self, in: context) { $0.title == markerTitle || свои.contains($0.id) })
        учесть("TrainingSession", count(TrainingSession.self, in: context) { $0.cue == markerTitle || свои.contains($0.id) })
        учесть("TrainingStep", count(TrainingStep.self, in: context) { $0.cue == markerTitle || свои.contains($0.id) })
        учесть("Trip", count(Trip.self, in: context) { $0.destination == markerTitle || свои.contains($0.id) })
        учесть("Dog", count(Dog.self, in: context) { $0.name == markerTitle || свои.contains($0.id) })
        учесть("FamilyMember", count(FamilyMember.self, in: context) { $0.name == markerTitle || свои.contains($0.id) })
        учесть("LogEvent", count(LogEvent.self, in: context) {
            $0.authorName == markerTitle || $0.date < доПрограммы || свои.contains($0.id)
        })
        // Семь типов дописаны 14.10.2026 той же рукой, что завела их
        // в `create` и в `remove`. Предикаты здесь обязаны совпадать
        // с предикатами удаления слово в слово: разойдутся — и остаток
        // будет считаться не по тому признаку, по которому удалялся,
        // то есть «ничего не осталось» станет утверждением про другой
        // вопрос.
        учесть("CareTask", count(CareTask.self, in: context) { $0.title == markerTitle || свои.contains($0.id) })
        учесть("WeightEntry", count(WeightEntry.self, in: context) { $0.date < доПрограммы || свои.contains($0.id) })
        учесть("Clinic", count(Clinic.self, in: context) { $0.name == markerTitle || свои.contains($0.id) })
        учесть("LabResult", count(LabResult.self, in: context) { $0.laboratory == markerTitle || свои.contains($0.id) })
        учесть("VetVisit", count(VetVisit.self, in: context) { $0.doctor == markerTitle || свои.contains($0.id) })
        учесть("Diagnosis", count(Diagnosis.self, in: context) { $0.wording == markerTitle || свои.contains($0.id) })
        учесть("Prescription", count(Prescription.self, in: context) { $0.number == markerTitle || свои.contains($0.id) })
        return найдено
    }

    @MainActor
    private static func count<T: PersistentModel>(
        _ type: T.Type, in context: ModelContext, where matches: (T) -> Bool
    ) -> Int {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter(matches).count
    }

    /// Выборка и удаление по признаку. Предикат обычный, а не
    /// `#Predicate`: он проверяет метку, которой нет у настоящих записей,
    /// и читаемость здесь важнее скорости — объектов единицы.
    @MainActor
    private static func delete<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext,
        where matches: (T) -> Bool
    ) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return 0 }
        let mine = all.filter(matches)
        for object in mine { context.delete(object) }
        return mine.count
    }
}
#endif
