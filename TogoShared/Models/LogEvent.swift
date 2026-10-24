import Foundation
import SwiftData

/// Одна запись ленты дня. Всё, что видит человек на главном экране, — это они.
@Model
final class LogEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = LogKind.note.rawValue

    /// Кто записал. Инициал показывается в ленте только когда в семье
    /// больше одного человека: одному себе представляться незачем.
    var authorName: String = ""

    /// Дошла ли запись до остальных.
    ///
    /// Обмен между устройствами есть (`FamilySync`), но доставку отдельной
    /// строки он не подтверждает: движок отправляет пачками и о судьбе
    /// каждой записи не отчитывается. Поэтому здесь всё ещё всегда `true`,
    /// и в интерфейсе поле намеренно не показывается — зелёная галочка
    /// «синхронизировано» у каждой записи была бы украшением,
    /// притворяющимся сведениями.
    var isSynced: Bool = true

    var note: String?

    // MARK: Откуда запись взялась

    /// **Когда записали**, в отличие от `date` — когда произошло.
    ///
    /// До 21.09.2026 они всегда совпадали, и отличить отметку в моменте
    /// от внесённой задним числом было нечем. А отличать надо: две недели
    /// семья давала таблетки и кормила, не отмечая, и дыру закрывают
    /// по памяти. Запись по памяти — полноценная запись, но другого
    /// происхождения.
    ///
    /// Пусто у всего, что записано до появления поля: там `date`
    /// и есть момент записи.
    var enteredAt: Date?

    /// Происхождение записи. Сырое значение — `RecordOrigin.rawValue`.
    ///
    /// Типизированное перечисление, а не свободный текст: в записи
    /// не должно появляться строк от человека, то же правило, что
    /// у журнала действий.
    var originRaw: String?

    var origin: RecordOrigin {
        get { originRaw.flatMap(RecordOrigin.init(rawValue:)) ?? .logged }
        set { originRaw = newValue == .logged ? nil : newValue.rawValue }
    }

    /// Запись внесена не в момент события.
    var isRecalled: Bool { origin != .logged }

    /// Известен **день**, а не час.
    ///
    /// Так выглядит всё, что восстановлено по памяти: «13 сентября был
    /// понос» — правда, «13 сентября в 14:02 был понос» — выдумка.
    /// Час в таких записях не подставляется ничем: `date` хранит начало
    /// дня, а это поле говорит, что точнее ничего не известно.
    ///
    /// Нужно отдельно от `origin`, потому что это разные вещи: запись
    /// можно внести задним числом и точно помнить час, а можно
    /// не помнить его и записав в тот же день.
    var isDayOnly: Bool = false

    // Выход
    var outcomeRaw: String?
    var askSignalRaw: String?
    var durationSeconds: Int?

    // Стул
    var stoolFormRaw: String?
    var stoolFlagsRaw: [String] = []

    // Еда, вода, лакомство
    var grams: Int?
    var milliliters: Int?
    var fromPortion: Bool = false

    // Срыв на прогулке
    //
    // # Читателя у этих двух полей нет, и это РЕШЕНИЕ, а не долг
    //
    // Пишутся в двух местах (`Needs/WalkMode.swift`, `Incident/IncidentSheet.swift`),
    // читающего экрана нет. В эталоне v10 на этом месте стоит «Порог
    // реакций» (`29-…/30-screens.jpg`): «больших реакций в неделю 3 ↓ с 5»,
    // дистанция, список «на что реагирует».
    //
    // **Экрана не будет.** Решение Виктории 24.10.2026 дословно: «лучше
    // спрашивать сразу у человека в момент того как он доказал что было
    // инцидент что произошло». То есть вопрос задаётся там, где человек
    // помнит ответ, — в момент срыва, — а не складывается в статистику,
    // которую он пойдёт читать отдельно.
    //
    // Поэтому поля остаются **входом без витрины**, намеренно: ответ
    // человека уезжает в запись события и дальше к врачу вместе с ней.
    // Удалять их нельзя — это данные, которые человек ввёл руками.
    //
    // > **Не всякое поле без читателя — долг.** Здесь нет читающего
    // > ЭКРАНА, и это разное с «никто не читает»: запись живёт в журнале
    // > и в сводке врачу. Сторож на «поле без читателя» на них покраснеет
    // > — у него тут ложное срабатывание, и причина записана здесь.
    var reactionTriggerRaw: String?
    var reactionDistanceRaw: String?

    // Инцидент
    var incidentKindRaw: String?
    var incidentDetailRaw: String?
    var toldFamily: Bool = false

    // Ссылки
    var trainingSessionID: UUID?
    var medicationID: UUID?
    var careTaskID: UUID?
    /// К какой прогулке относится отметка.
    ///
    /// Раньше связью служила подпись «на прогулке» словами. Из-за этого
    /// в ленте одна прогулка рассыпалась на отдельные строки: сама
    /// прогулка стояла в момент выхода, её отметки — в момент возвращения,
    /// и между ними могло лежать полчаса и другие записи. Понять, что это
    /// одно событие, можно было только сопоставив времена в уме.
    var walkEventID: UUID?

    /// Удаление обратимо 5 секунд и оставляет след в истории:
    /// молчаливой перезаписи и тихого удаления в приложении нет нигде.
    var deletedAt: Date?
    var deletedBy: String?

    /// Кто поправил запись последним.
    ///
    /// **У удаления автор был, у правки — нет, хотя экран правки есть.**
    /// `changedAt` знает КОГДА, `deletedBy` знает КТО УДАЛИЛ, а «кто
    /// исправил» не знал никто. В дневнике на семью это и есть главный
    /// вопрос к исправленной записи: граммы поправил тот, кто кормил,
    /// или тот, кто пришёл следом и решил, что было иначе.
    ///
    /// `nil` — запись никто не правил после создания.
    var editedBy: String?

    /// Когда этот телефон в последний раз трогал запись.
    ///
    /// Ставится сама при сохранении — не руками на каждом экране, иначе
    /// её забудут ровно там, где она нужнее всего. Нужна общему дневнику:
    /// когда два телефона спорят об одних граммах, выигрывает тот,
    /// кто правил позже.
    var changedAt: Date = Date()

    var dog: Dog?

    init(kind: LogKind, date: Date = Date(), authorName: String) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.date = date
        self.authorName = authorName
    }

    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var outcome: OutingOutcome? {
        get { outcomeRaw.flatMap(OutingOutcome.init) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var askSignal: AskSignal? {
        get { askSignalRaw.flatMap(AskSignal.init) }
        set { askSignalRaw = newValue?.rawValue }
    }

    var stoolForm: StoolForm? {
        get { stoolFormRaw.flatMap(StoolForm.init) }
        set { stoolFormRaw = newValue?.rawValue }
    }

    var stoolFlags: Set<StoolFlag> {
        get { Set(stoolFlagsRaw.compactMap(StoolFlag.init)) }
        set { stoolFlagsRaw = newValue.map(\.rawValue).sorted() }
    }

    var incidentKind: IncidentKind? {
        get { incidentKindRaw.flatMap(IncidentKind.init) }
        set { incidentKindRaw = newValue?.rawValue }
    }

    var vomitDetail: VomitDetail? {
        get { incidentDetailRaw.flatMap(VomitDetail.init) }
        set { incidentDetailRaw = newValue?.rawValue }
    }

    var reactionTrigger: ReactionTrigger? {
        get { reactionTriggerRaw.flatMap(ReactionTrigger.init) }
        set { reactionTriggerRaw = newValue?.rawValue }
    }

    var reactionDistance: ReactionDistance? {
        get { reactionDistanceRaw.flatMap(ReactionDistance.init) }
        set { reactionDistanceRaw = newValue?.rawValue }
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Кровь — единственный флаг, поднимающий бытовую запись в терракот.
    var raisesAlarm: Bool {
        if stoolFlags.contains(where: \.raisesAlarm) { return true }
        if let vomitDetail, vomitDetail.raisesAlarm { return true }
        return false
    }

    /// Подпись под строкой ленты: «стул как всегда · моча».
    var subtitle: String? {
        var parts: [String] = []
        if let outcome { parts.append(outcome.shortTitle) }
        if let stoolForm { parts.append(stoolForm.title.lowercased()) }
        if !stoolFlags.isEmpty { parts.append(stoolFlags.map { $0.title.lowercased() }.joined(separator: ", ")) }
        if let grams { parts.append(String(localized: "\(grams) г")) }
        if let milliliters { parts.append(String(localized: "\(milliliters) мл")) }
        if let durationSeconds, durationSeconds > 0 { parts.append(String(localized: "\(durationSeconds / 60) мин")) }
        if let reactionTrigger { parts.append(reactionTrigger.title.lowercased()) }
        if let reactionDistance { parts.append(reactionDistance.title.lowercased()) }
        if let incidentKind { parts.append(incidentKind.title.lowercased()) }
        if let vomitDetail { parts.append(vomitDetail.title) }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
