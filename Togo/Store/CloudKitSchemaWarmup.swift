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
/// Порядок работы:
/// 1. Отладочная сборка на устройстве с живым Apple ID, iCloud включён.
/// 2. «Настройки» → «Отладка · завести зеркало в iCloud».
/// 3. Подождать минуту при живой сети — зеркало отправит записи.
/// 4. `Tools/deploy_cloudkit_schema.sh` — он скажет, каких типов ещё нет.
/// 5. «Отладка · убрать прогрев», когда все шестнадцать на месте.
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
        let objects: [any PersistentModel] = [
            DayOut(startedAt: markerDate, plannedHours: 1),
            DogDocument(title: markerTitle),
            DoseRecord(scheduledAt: markerDate),
            Episode(title: markerTitle, detail: markerTitle, startedAt: markerDate),
            FoodStock(kind: .dry, brand: markerTitle, packGrams: 1, packsLeft: 1,
                      gramsPerDay: 1, countedAt: markerDate),
            HeatRecord(startedAt: markerDate, note: markerTitle),
            Medication(name: markerTitle, doseText: markerTitle, times: [0]),
            ProcedureSkill(title: markerTitle, detail: markerTitle),
            TrainingSession(cue: markerTitle, place: markerTitle, person: markerTitle,
                            distanceMeters: 0),
            TrainingStep(cue: markerTitle, place: markerTitle, person: markerTitle,
                         distanceMeters: 0),
            Trip(destination: markerTitle, startDate: markerDate, endDate: markerDate,
                 transport: .car),
            собакаСоВсемиПолями(),
            участникСоВсемиПолями(),
            записьСоВсемиПолями(),
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
        return запись
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
