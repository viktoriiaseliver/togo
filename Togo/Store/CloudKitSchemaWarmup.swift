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
        removed += delete(DayOut.self, in: context) { $0.startedAt == markerDate }
        removed += delete(DogDocument.self, in: context) { $0.title == markerTitle }
        removed += delete(DoseRecord.self, in: context) { $0.scheduledAt == markerDate }
        removed += delete(Episode.self, in: context) { $0.title == markerTitle }
        removed += delete(FoodStock.self, in: context) { $0.brand == markerTitle }
        removed += delete(HeatRecord.self, in: context) { $0.startedAt == markerDate }
        removed += delete(Medication.self, in: context) { $0.name == markerTitle }
        removed += delete(ProcedureSkill.self, in: context) { $0.title == markerTitle }
        removed += delete(TrainingSession.self, in: context) { $0.cue == markerTitle }
        removed += delete(TrainingStep.self, in: context) { $0.cue == markerTitle }
        removed += delete(Trip.self, in: context) { $0.destination == markerTitle }
        removed += delete(Dog.self, in: context) { $0.name == markerTitle }
        removed += delete(FamilyMember.self, in: context) { $0.name == markerTitle }
        removed += delete(LogEvent.self, in: context) { $0.authorName == markerTitle }
        try context.save()
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
        var осталось = 0
        осталось += count(DayOut.self, in: context) { $0.startedAt == markerDate }
        осталось += count(DogDocument.self, in: context) { $0.title == markerTitle }
        осталось += count(DoseRecord.self, in: context) { $0.scheduledAt == markerDate }
        осталось += count(Episode.self, in: context) { $0.title == markerTitle }
        осталось += count(FoodStock.self, in: context) { $0.brand == markerTitle }
        осталось += count(HeatRecord.self, in: context) { $0.startedAt == markerDate }
        осталось += count(Medication.self, in: context) { $0.name == markerTitle }
        осталось += count(ProcedureSkill.self, in: context) { $0.title == markerTitle }
        осталось += count(TrainingSession.self, in: context) { $0.cue == markerTitle }
        осталось += count(TrainingStep.self, in: context) { $0.cue == markerTitle }
        осталось += count(Trip.self, in: context) { $0.destination == markerTitle }
        осталось += count(Dog.self, in: context) { $0.name == markerTitle }
        осталось += count(FamilyMember.self, in: context) { $0.name == markerTitle }
        осталось += count(LogEvent.self, in: context) { $0.authorName == markerTitle }
        return осталось
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
