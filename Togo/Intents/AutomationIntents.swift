import AppIntents
import SwiftData

/// Отметки для «Команд» и автоматизаций: метка NFC у двери, «пришёл
/// домой», время суток, кнопка «Действие».
///
/// **Просьба Виктории 29.10.2026 — «работа через команды, чтобы отмечать
/// разные автоматизации».** До этого из «Команд» можно было поставить
/// пять вещей: пописал, стул, еда, прогулка и вопрос «давно ли гуляли».
/// Лужу дома, рвоту, дозу, воду, лакомство, короткий выход и заметку
/// можно было отметить только с экрана — то есть ровно там, где
/// автоматизация бессильна.
///
/// # Одна дверь на всех
///
/// Каждое действие здесь пишет через `QuickLog.записать` — ту же дверь,
/// что у голосовых «пописал» и «стул»: право (`QuickLog.можно`), сторож
/// дубля (`DuplicateGuard`), честный отказ на несохранившемся, журнал
/// действий и снимок виджета. Своей записи в дневник в этом файле нет
/// ни одной, и это проверяет `SingleDoorTests`: `LogEvent(kind:` здесь
/// не встречается.
///
/// # Лужа и кучка дома — инцидент
///
/// Решение Виктории того же дня: «всё, что дома про лужи и туалет, —
/// в инциденте». Поэтому «лужа дома» — это `.incident` + `.puddle`,
/// а не выход с исходом. Эпизод по инциденту поднимает `EpisodeRaiser`
/// — тот же, что у шторки «Что случилось»; туалет дома эпизода
/// не поднимает (у щенка их пять за день, `IncidentKind.raisesEpisode`).

// MARK: - Что выбирать в «Командах»

/// Форма стула — для действия «стул» и «стул дома».
///
/// Подписи — те же ключи каталога, что у чипов на экране (`StoolForm.title`):
/// одно и то же слово в двух местах не должно расходиться переводом.
nonisolated enum StoolFormChoice: String, AppEnum, CaseIterable {
    case hard, sausage, soft, mushy, liquid

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Форма")

    static let caseDisplayRepresentations: [StoolFormChoice: DisplayRepresentation] = [
        .hard: DisplayRepresentation(title: "Твёрдый"),
        .sausage: DisplayRepresentation(title: "Колбаска"),
        .soft: DisplayRepresentation(title: "Мягкий"),
        .mushy: DisplayRepresentation(title: "Кашица"),
        .liquid: DisplayRepresentation(title: "Лужа"),
    ]

    var form: StoolForm {
        switch self {
        case .hard: .hard
        case .sausage: .sausage
        case .soft: .soft
        case .mushy: .mushy
        case .liquid: .liquid
        }
    }
}

/// Как сходил на коротком выходе.
nonisolated enum OutingOutcomeChoice: String, AppEnum, CaseIterable {
    case urine, stool, both, none

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Как сходил?")

    static let caseDisplayRepresentations: [OutingOutcomeChoice: DisplayRepresentation] = [
        .urine: DisplayRepresentation(title: "Пописал", image: .init(systemName: "drop")),
        .stool: DisplayRepresentation(title: "Стул", image: .init(systemName: "leaf")),
        .both: DisplayRepresentation(title: "И то и другое"),
        .none: DisplayRepresentation(title: "Не сходил"),
    ]

    var outcome: OutingOutcome {
        switch self {
        case .urine: .urine
        case .stool: .stool
        case .both: .both
        case .none: .none
        }
    }
}

/// Отказ, который надо сказать словами, — с текстом, собранным на месте.
///
/// Для автоматизации отказ должен быть ОТКАЗОМ: «Команды» показывают
/// ошибку и останавливают цепочку, а ответ-диалог прошёл бы за успех.
/// Метка у двери, «отметившая» дозу, которую на самом деле не отметили,
/// — это вторая таблетка у следующего человека.
nonisolated struct ОтказКоманды: Error, CustomLocalizedStringResourceConvertible {
    let текст: String
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: текст)
    }
}

// MARK: - Инциденты

extension QuickLog {
    /// Инцидент через общую дверь, и следом — эпизод.
    ///
    /// Эпизод поднимается только у легшей записи: `запись == nil` значит
    /// «дубль», и продлевать эпизод чужой записью нельзя. `appState` нет —
    /// эпизод ляжет в базу, экран подтянет его при открытии
    /// (`EpisodeRaiser`, голова).
    static func инцидент(_ вид: IncidentKind,
                         configure: (LogEvent) -> Void = { _ in }) throws -> String {
        let итог = try записать(.incident) {
            $0.incidentKind = вид
            $0.toldFamily = вид.notifiesFamilyByDefault
            configure($0)
        }
        guard итог.запись != nil else { return итог.ответ }
        let ответ = String(localized: "Записала · \(вид.title.lowercased()) · \(итог.собака.displayName)")
        guard EpisodeRaiser.afterIncident(dog: итог.собака, context: итог.контекст,
                                          appState: nil) else {
            return ответ + " · " + String(localized: "эпизод не сохранился — открой Togo")
        }
        // Эпизод гасит вердикты «просится» — виджет должен узнать о нём
        // сейчас, а не при следующей записи.
        WidgetRefresh.сейчас()
        return ответ
    }
}

struct MarkPuddleIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить лужу дома"
    static let description = IntentDescription("Записывает лужу в доме как инцидент.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.инцидент(.puddle)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MarkStoolIndoorsIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить стул дома"
    static let description = IntentDescription("Записывает стул в доме как инцидент. Форму можно указать сразу или уточнить потом.")
    static let openAppWhenRun = false

    /// Форма не обязательна: метка у двери её не знает. Но спрашивается
    /// она у стула дома не зря — без неё жидкий стул дома выпал бы
    /// из сводки врачу (решение 29.10.2026).
    @Parameter(title: "Форма")
    var form: StoolFormChoice?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let форма = form?.form
        var message = try QuickLog.инцидент(.stoolIndoors) { $0.stoolForm = форма }
        if let форма { message += " · " + форма.title.lowercased() }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MarkVomitIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить рвоту"
    static let description = IntentDescription("Записывает рвоту как инцидент. Чем именно — можно уточнить потом.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.инцидент(.vomit)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Еда, вода, лакомство

/// Вода — без количества, нарочно.
///
/// Ручную запись воды экран снял: «сколько выпила — человек не знает,
/// миска стоит целый день, и цифра бралась из воздуха» (`LogKind.water`).
/// Для автоматизации («налила воды утром») смысл другой — отметка
/// момента, а не объёма, и миллилитров здесь нет по той же причине,
/// по которой их убрали с экрана.
struct MarkWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить воду"
    static let description = IntentDescription("Отмечает, что налили воды. Без количества: сколько выпито, не знает никто.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.water)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MarkTreatIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить лакомство"
    static let description = IntentDescription("Записывает лакомство в дневник Togo.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.treat)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Короткий выход

/// Выход по нужде с исходом — для метки у двери и «пришёл домой».
///
/// Исход не обязателен, и у кобеля это правило, а не послабление:
/// «поход на улицу для кобеля = туалет, незачем указывать мочу»
/// (решение Виктории 29.10.2026). Выход без исхода `ToiletClock`
/// читает у кобеля как мочу; у суки — как выход без ответа, и счёт
/// идёт от него запасным якорем. Мочу за человека в базу не кладём:
/// запись потом читает врач.
struct MarkOutingIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить короткий выход"
    static let description = IntentDescription("Записывает выход по нужде. Как сходил — можно указать или оставить пустым.")
    static let openAppWhenRun = false

    @Parameter(title: "Как сходил?")
    var outcome: OutingOutcomeChoice?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let исход = outcome?.outcome
        var message = try QuickLog.record(.outing) { $0.outcome = исход }
        if let исход { message += " · " + исход.shortTitle }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Заметка

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать заметку"
    static let description = IntentDescription("Добавляет в дневник Togo заметку с текстом.")
    static let openAppWhenRun = false

    @Parameter(title: "Заметка", requestValueDialog: "Что записать?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let текст = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустая заметка — не запись, а нажатие без слов. Сказать
        // «записала» на пустоту значило бы соврать про то, что в ленте.
        guard !текст.isEmpty else {
            throw ОтказКоманды(текст: String(localized: "Заметка пустая — записывать нечего."))
        }
        let message = try QuickLog.record(.note) { $0.note = текст }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Доза

/// Лекарство собаки — чтобы в «Командах» можно было выбрать, какое.
nonisolated struct MedicationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Лекарство")
    static let defaultQuery = MedicationQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Лекарства открытой собаки, кроме поставленных на паузу.
///
/// Чтение базы — на главном акторе, как у остальных интентов: модели
/// SwiftData живут там, а наружу уходят только имя и id. Сами тип
/// и запрос `nonisolated` по той же причине, что `WalkMarkKind`:
/// требования `AppEntity` неизолированные, а у цели приложения
/// изоляция по умолчанию — главный актор.
nonisolated struct MedicationQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MedicationEntity] {
        try await Self.все().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MedicationEntity] {
        try await Self.все()
    }

    @MainActor
    private static func все() throws -> [MedicationEntity] {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }
        return dog.medications
            .filter { !$0.isPaused }
            .map { MedicationEntity(id: $0.id, name: $0.name) }
    }
}

/// «Дал лекарство» без экрана.
///
/// **Самое дорогое действие из всех, и потому самое осторожное.**
/// Ошибка здесь — не лишняя строка в ленте, а вторая таблетка: отметка
/// приёма снимает напоминания, и второй человек видит дозу данной.
/// Поэтому интент не угадывает: доза отмечается, только если она одна
/// и открыта. Всё остальное — отказ словами, а не выбор за человека.
struct GiveDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить, что дал лекарство"
    static let description = IntentDescription("Отмечает дозу по расписанию, которая ждёт сейчас. Если ждут несколько — назови лекарство.")
    static let openAppWhenRun = false

    @Parameter(title: "Лекарство")
    var medication: MedicationEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try ДозаБезЭкрана.отметить(лекарство: medication?.id)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@MainActor
enum ДозаБезЭкрана {

    /// Насколько раньше часа по расписанию дозу можно отметить голосом.
    ///
    /// Час — не правило лечения, а граница угадывания: дальше этого
    /// «дал лекарство» в 13:00 могло бы отметить вечернюю дозу 21:00,
    /// и вечером её не дали бы вовсе. Раньше — только с экрана, где
    /// видно, какая доза отмечается.
    static let раньшеНеБолее: TimeInterval = 60 * 60

    static func отметить(лекарство id: UUID?, now: Date = Date()) throws -> String {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }
        // Право — отдельное (`.giveDose`), и спрашивается ДО отметки:
        // отметка приёма — не строка ленты, её `QuickLog` не охраняет.
        guard QuickLog.можно(.dose, in: context) else { throw QuickLogError.noPermission }

        // Отметки на сегодня заводятся лениво — тем же вызовом, что
        // при открытии «Сегодня». Без него у утренней дозы, которую ещё
        // никто не открывал на экране, отметки нет, и голос ответил бы
        // «доз нет» при дозе по расписанию.
        DoseScheduler.ensureDoses(for: dog, on: now, context: context)

        // Курс закончен — доз по расписанию нет, даже если от него
        // остались неотмеченные отметки дня: их не заводит и не показывает
        // никто (`DoseScheduler.ensureDoses` начинается с той же проверки).
        let схемы = dog.isOnTreatment
            ? dog.medications.filter { !$0.isPaused && (id == nil || $0.id == id) }
            : []
        let ждут = схемы.flatMap { схема in
            схема.doses
                .filter { Calendar.current.isDate($0.scheduledAt, inSameDayAs: now) }
                .filter { !$0.isGiven && !$0.isSkipped && $0.cancelledAt == nil }
                .filter { $0.scheduledAt.timeIntervalSince(now) <= Self.раньшеНеБолее }
                .map { (схема: схема, доза: $0) }
        }

        guard let первая = ждут.first else {
            if let id, let схема = dog.medications.first(where: { $0.id == id }) {
                throw ОтказКоманды(текст: String(localized: "\(схема.name): сейчас доз по расписанию нет."))
            }
            throw ОтказКоманды(текст: String(localized: "Сейчас доз по расписанию нет."))
        }
        // Две ждущие дозы — пропущенная утренняя и дневная, или два
        // лекарства в один час. Какую из них дали, голос не знает,
        // а угадывать дозу нельзя.
        guard ждут.count == 1 else {
            throw ОтказКоманды(текст: String(localized: "Сейчас ждут несколько доз — назови лекарство или отметь в Togo."))
        }
        let (схема, доза) = первая

        // «Беру на себя» — договорённость семьи о том, кто даёт. Отметить
        // поверх неё голосом значило бы дать вторую.
        if доза.claimIsActive(at: now), let кто = доза.claimedBy, кто != AppState.storedUserName {
            throw ОтказКоманды(текст: String(localized: "\(кто) берёт эту дозу на себя. Открой Togo, если дал ты."))
        }

        // Доза после еды открывается от отметки кормления — тем же
        // правилом, что выключает кнопку на экране (`DoseGate`).
        let ворота = DoseGate.state(for: схема, events: dog.events,
                                    scheduledAt: доза.scheduledAt, now: now)
        if !ворота.isOpen, let подпись = DoseGate.caption(ворота, now: now) {
            throw ОтказКоманды(текст: "\(схема.name): \(подпись)")
        }

        // Порядок — как у «Сегодня» (`DayPlanActions.complete`): сперва
        // отметка приёма, пустой ответ останавливает всё; потом строка
        // в ленте; напоминания снимаются только у легшей отметки.
        guard let отметка = DoseScheduler.markGiven(схема, scheduledAt: доза.scheduledAt,
                                                    by: AppState.storedUserName, at: now,
                                                    context: context) else {
            throw QuickLogError.storageUnavailable
        }
        ReminderScheduler.cancelDose(отметка)

        var ответ = String(localized: "Записала · \(схема.name) · \(Fmt.clock(доза.scheduledAt))")
        do {
            let итог = try QuickLog.записать(.dose) {
                $0.note = схема.name
                $0.medicationID = схема.id
            }
            if итог.запись == nil { ответ = итог.ответ }
        } catch {
            // Доза уже отмечена — и это главное, промолчать об этом нельзя:
            // человек повторил бы команду. Не легла только строка ленты.
            return String(localized: "Доза отмечена, а строка в ленте не записалась — открой Togo.")
        }

        if let окно = FeedingGate.block(for: dog.medications, now: now)?.freeAt, окно > now {
            ответ += " · " + String(localized: "не кормить до \(Fmt.clock(окно))")
        }
        return ответ
    }
}
