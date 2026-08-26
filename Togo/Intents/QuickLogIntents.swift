import AppIntents
import SwiftData
import ActivityKit

/// Отметки, которые ставятся не доставая телефон.
///
/// Кнопка громкости для этого не годится: Apple разрешает перехватывать
/// её только затвору камеры, и приложение с такой механикой в App Store
/// не пройдёт. Зато есть четыре законных пути, и все они ведут в один
/// и тот же код — сюда:
///
/// * **кнопка «Действие»** на iPhone 15 Pro и новее — нажатие сбоку;
/// * **Пункт управления и экран блокировки** — свайп и тап;
/// * **Siri и «Команды»** — голосом, в том числе с Apple Watch;
/// * **кнопки на живой активности** — прямо на заблокированном экране,
///   пока идёт прогулка.
///
/// Последнее и есть главный ответ: на улице телефон лежит в кармане,
/// а отметить надо здесь и сейчас.

// MARK: - Общая часть

/// Действия выполняются в процессе приложения, а не расширения: только
/// оттуда виден дневник. Для живой активности это гарантирует
/// `LiveActivityIntent`, для остальных — то, что их запускает система
/// от имени самого приложения.
@MainActor
enum QuickLog {
    /// Записать и ответить словами: голосом человек не видит экрана,
    /// и подтверждение должно быть в самом ответе.
    static func record(_ kind: LogKind, configure: (LogEvent) -> Void = { _ in }) throws -> String {
        guard let container = Persistence.shared else {
            throw QuickLogError.storageUnavailable
        }
        let context = ModelContext(container)
        guard let dog = try activeDog(in: context) else {
            throw QuickLogError.noDog
        }

        let event = LogEvent(kind: kind, date: Date(), authorName: AppState.storedUserName)
        configure(event)
        event.dog = dog
        context.insert(event)
        try context.save()

        return "Записала · \(kind.title.lowercased()) · \(dog.name)"
    }

    /// Та собака, что открыта в приложении. Дневники разных собак
    /// не смешиваются, и голосовая отметка не должна их путать.
    static func activeDog(in context: ModelContext) throws -> Dog? {
        let dogs = try context.fetch(FetchDescriptor<Dog>())
        let selected = UserDefaults.standard.string(forKey: AppState.Keys.activeDog).flatMap(UUID.init)
        return dogs.first { $0.id == selected } ?? dogs.first
    }
}

enum QuickLogError: Error, CustomLocalizedStringResourceConvertible {
    case noDog
    case storageUnavailable
    case noWalk

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDog: "Собака ещё не заведена — открой Того и добавь её."
        case .storageUnavailable: "Дневник сейчас недоступен. Открой Того."
        case .noWalk: "Прогулка не идёт."
        }
    }
}

// MARK: - Отметки

struct MarkPeeIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить, что пописал"
    static let description = IntentDescription("Записывает выход по нужде в дневник Того.")
    /// Приложение не открывается: смысл в том, чтобы не доставать телефон.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.outing) { $0.outcome = .urine }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MarkStoolIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить стул"
    static let description = IntentDescription("Записывает стул в дневник Того. Форму можно уточнить потом.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.stool)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать кормление"
    static let description = IntentDescription("Записывает еду. Граммы берутся из режима питания.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }

        let grams = dog.servingGrams
        let message = try QuickLog.record(.meal) {
            $0.grams = grams
            $0.note = dog.foodBrand.isEmpty ? nil : dog.foodBrand
        }
        return .result(dialog: IntentDialog(stringLiteral: "\(message) · \(grams) г"))
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать, что попил"
    static let description = IntentDescription("Записывает воду в дневник Того.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try QuickLog.record(.water) { $0.milliliters = 100 }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Сколько он уже дома

struct TimeIndoorsIntent: AppIntent {
    static let title: LocalizedStringResource = "Давно ли гуляли"
    static let description = IntentDescription("Отвечает, сколько прошло с последнего выхода на улицу.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let container = Persistence.shared else { throw QuickLogError.storageUnavailable }
        let context = ModelContext(container)
        guard let dog = try QuickLog.activeDog(in: context) else { throw QuickLogError.noDog }

        let blocks = TimelineBuilder.blocks(Diary.active(dog.events))
        guard let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: Date(), threshold: 0) else {
            return .result(dialog: "Сегодня ещё не выходили.")
        }
        return .result(dialog: IntentDialog(
            stringLiteral: "\(dog.name) дома \(Fmt.duration(indoors)) с прошлого выхода."
        ))
    }
}

// MARK: - Что предлагать без настройки

/// Готовые фразы: работают сразу после установки, настраивать ничего
/// не надо. Это и есть условие, при котором голосом вообще пользуются.
struct TogoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkPeeIntent(),
            phrases: ["Отметить в \(.applicationName), что пописал",
                      "\(.applicationName): пописал"],
            shortTitle: "Пописал",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: MarkStoolIntent(),
            phrases: ["Отметить стул в \(.applicationName)",
                      "\(.applicationName): стул"],
            shortTitle: "Стул",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: ["Записать кормление в \(.applicationName)",
                      "\(.applicationName): покормила"],
            shortTitle: "Покормила",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: TimeIndoorsIntent(),
            phrases: ["Давно ли гуляли в \(.applicationName)",
                      "\(.applicationName): давно ли гуляли"],
            shortTitle: "Давно ли гуляли",
            systemImageName: "clock"
        )
    }
}
