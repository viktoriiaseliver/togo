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

        guard можно(kind, in: context) else {
            throw QuickLogError.noPermission
        }

        let event = LogEvent(kind: kind, date: Date(), authorName: AppState.storedUserName)
        configure(event)

        // Правило дубля здесь такое же, как на экране, и по той же причине.
        // До 23.09.2026 его тут не было вовсе: сказать «покорми» дважды
        // подряд можно было без всякой защиты — а голосом и кнопкой
        // «Действие» жмут как раз не глядя, то есть второй раз вероятнее,
        // чем на экране. Отвечаем словами, а не молча: у интента нет тоста,
        // и ответ — единственное, что человек услышит.
        if let recent = DuplicateGuard.recent(of: kind, dog: dog, at: event.date,
                                              like: event, in: context) {
            UsageLog.note(.record, kind.rawValue, outcome: .duplicate)
            return DuplicateGuard.message(kind, at: recent.date)
        }

        event.dog = dog
        context.insert(event)
        try context.save()

        // Без этой строки журнал не знает о записях голосом вовсе:
        // в замере 23.09 их нет ни одной, и нельзя сказать, не пользуются
        // ими или путь размечен не был.
        UsageLog.note(.record, kind.rawValue, on: .other)

        return String(localized: "Записала · \(kind.title.lowercased()) · \(dog.displayName)")
    }

    /// Можно ли этому телефону записывать голосом и кнопкой «Действие».
    ///
    /// **Почему не через `AppState`.** Интент живёт в своём процессе,
    /// `AppState` там нет, и роль в него не восстановить: она вообще
    /// не хранится на диске — при запуске её вычисляет `adoptMe`
    /// из списка семьи. Поэтому здесь тот же путь, только короче:
    /// своя карточка ищется по `family.me`, а права берутся у неё.
    ///
    /// **Решение общее с экранами** — `FamilyResolver`. Первая
    /// редакция повторяла его здесь своими словами и разошлась
    /// в двух местах сразу: пустая семья у гостя значила «можно всё»
    /// (а на экранах — «наблюдатель»), и единственная карточка бралась
    /// любая (а на экранах — только помеченная `isMe`). Обе дыры
    /// открывались у гостя, пока синхронизация не доехала, и обе
    /// выдавали право на дозу.
    static func можно(_ kind: LogKind, in context: ModelContext,
                      гость: Bool = SharedZoneOwner.isGuest) -> Bool {
        let семья = (try? context.fetch(FetchDescriptor<FamilyMember>())) ?? []
        let запомненный = UserDefaults.standard.string(forKey: AppState.Keys.myMember)
            .flatMap(UUID.init)
        // Назначение берётся здесь, а не внутри `права(…)`: у функции
        // оно параметр, а не глобальное чтение, — иначе её нельзя было бы
        // проверить тестом, не трогая хранилище телефона. Зовут её два
        // входа, и оба обязаны передать одно и то же.
        return FamilyResolver
            .права(среди: семья, запомненный: запомненный, гость: гость,
                   назначение: НазначениеПоОбмену.текущее)
            .contains(kind.requiredPermission)
    }

    /// Та собака, что открыта в приложении. Дневники разных собак
    /// не смешиваются, и голосовая отметка не должна их путать.
    static func activeDog(in context: ModelContext) throws -> Dog? {
        // Второй резолвер активной собаки — для Siri и виджета.
        // Фильтр тот же, что в `AppState.activeDog(from:)`: голос,
        // попавший на безымянную запись, отметит кормление не той
        // собаке и промолчит об этом.
        let dogs = try context.fetch(FetchDescriptor<Dog>()).shownToPerson
        let selected = UserDefaults.standard.string(forKey: AppState.Keys.activeDog).flatMap(UUID.init)
        return dogs.first { $0.id == selected } ?? dogs.first
    }
}

enum QuickLogError: Error, CustomLocalizedStringResourceConvertible {
    case noDog
    case storageUnavailable
    case noWalk
    case noPermission

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDog: "Собака ещё не заведена — открой Togo и добавь её."
        case .storageUnavailable: "Дневник сейчас недоступен. Открой Togo."
        case .noWalk: "Прогулка не идёт."
        // **Третья дверь того же запрета, и единственная, где человек
        // не видит экрана вовсе** — Siri и виджет. Право берётся тем же
        // путём (`можно(_:in:гость:)` → `FamilyResolver.права`), запрет
        // тот же `.logBasics`, что в `EventLog` и `DayPlanActions`.
        //
        // Текст переписан 14.10.2026, и **устарел он не сам — его
        // состарила починка в соседнем файле.** «Спроси того, кто им
        // делится» было честно ровно до тех пор, пока у человека
        // не было своего выхода. Выход появился в то же утро: права
        // берутся из карточки на ЕГО телефоне, и опознать себя он может
        // сам. Старый совет отправлял его к другому человеку, то есть
        // предлагал дорогу длиннее имеющейся.
        //
        // Адрес назван **словами, а не стрелкой**: эту строку читает
        // озвучка, и «Семья → Это я» в ней звучит как бессмыслица.
        // Из существующих ключей он здесь не собирается — `AppIntents`
        // разбираются статически, и `String(localized:)` вместо литерала
        // дал бы пустую фразу в «Командах» при собравшемся коде.
        //
        // Цена замера названа: старый ключ осиротеет, с ним уйдут три
        // перевода — все три `needs_review`, ни одного готового.
        //
        // **ДОЛГ ПЕРЕВОДА ОТКРЫТ И НЕВИДИМ ДЛЯ ВСЕХ ТРЁХ СТОРОЖЕЙ.**
        // Замер `togo-russian-testflight-qa` 14.10.2026, три разные
        // причины промолчать — и ни одна не про то, что текст вне
        // каталога:
        //
        //     LocalizationDebtTests         корень TogoShared (:104-107);
        //                                   этот файл в Togo/Intents/ — вне области
        //     СвойствоМимоКаталогаTests     область есть, ось «кириллица
        //                                   справа от `=` у получателя»;
        //                                   здесь возврат из switch — мимо
        //     FallbackLiteralTests          ось «кириллица справа от `??`» — мимо
        //
        // Пометка стоит здесь ровно потому, что механизма, который
        // заметит этот долг, нет: **невидимый долг через месяц читается
        // как «так и задумано»**. Француз и украинец услышат в «Командах»
        // русскую фразу, и единственный свидетель этому — человек
        // с телефоном: `AppIntents` в XCUITest не вызываются, кадром
        // не берутся. Та же форма, что у заголовка `CKShare`
        // в системной шторке: поверхность есть, свидетеля нет.
        //
        // внутреннее: литерал вынужден устройством AppIntents — они
        // разбираются статически, и String(localized:) дал бы пустую
        // фразу в «Командах» при собравшемся коде. Перевод возможен
        // только через .lproj расширения; долг на en/fr/uk открыт.
        case .noPermission: "Записывать в этот дневник тебе не разрешено. Открой Togo, вкладку «Семья», и нажми «Это я»."
        }
    }
}

// MARK: - Отметки

struct MarkPeeIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить, что пописал"
    static let description = IntentDescription("Записывает выход по нужде в дневник Togo.")
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
    static let description = IntentDescription("Записывает стул в дневник Togo. Форму можно уточнить потом.")
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
        let indoors = TimelineBuilder.timeIndoorsNow(blocks, now: Date(), threshold: 0)
        guard let indoors else { return .result(dialog: "Сегодня ещё не выходили.") }

        return .result(dialog: IntentDialog(stringLiteral: Self.ответ(
            dogName: dog.displayName,
            indoors: indoors,
            lastOutingEndedAt: blocks.last(where: \.isOuting)?.endedAt
        )))
    }

    /// Что Siri скажет вслух. Вынесено из `perform` нарочно: собрать
    /// `IntentResult` в тесте нельзя, а проверять тут надо две вещи,
    /// на которых приложение уже обжигалось.
    ///
    /// **Первая — потолок.** До 24.09 его здесь не было вовсе: на тех
    /// же данных, на которых экран честно говорит «Выходов нет с 3 сент.»,
    /// Siri отвечала «Стич дома 434 ч с прошлого выхода». Экран починили
    /// 21.09, голос читал ту же величину мимо правила — починка на одной
    /// поверхности из двух.
    ///
    /// **Вторая — перевод.** `IntentDialog(stringLiteral:)` берёт уже
    /// собранную строку: интерполяция случилась раньше, и в каталог
    /// за переводом никто не пойдёт. Перевод `%@ дома %@ с прошлого
    /// выхода.` лежал в каталоге на французском и украинском и не мог
    /// быть показан **ни разу** — полнота каталога тут не значит ничего.
    /// Лечится `String(localized:)`: ключ собирается тот же самый.
    static func ответ(dogName: String, indoors: TimeInterval,
                      lastOutingEndedAt: Date?) -> String {
        // Кличка приходит параметром, и пустой она быть может: эту
        // функцию зовёт не только экран. До 07.10.2026 голос произносил
        // « дома 3 ч с прошлого выхода.» — предложение без подлежащего,
        // начинающееся с пустого места. На слух это не «нет клички»,
        // а проглоченное слово.
        //
        // Ворота стоят ЗДЕСЬ, а не у вызывающего: функция чистая,
        // её зовут тестом напрямую, и правило, поставленное снаружи,
        // до этого вызова не дотянулось бы.
        let кличка = Fmt.dogNameOrFallback(dogName)
        if let тишина = OutingSilence.start(indoors: indoors,
                                            lastOutingEndedAt: lastOutingEndedAt) {
            return String(localized: "Выходов нет с \(Fmt.shortDay(тишина))")
        }
        return String(localized: "\(кличка) дома \(Fmt.duration(indoors)) с прошлого выхода.")
    }
}

// MARK: - Что предлагать без настройки

/// Готовые фразы: работают сразу после установки, настраивать ничего
/// не надо. Это и есть условие, при котором голосом вообще пользуются.
///
/// ## Почему интентов восемь, а готовых фраз пять
///
/// Здесь не было об этом ни слова, и отсутствие двух прогулочных
/// интентов читалось как пропуск («5 интентов из 7» — опись 24.10.2026).
/// Замер по коду даёт другое: **довод есть, и он уже сказан человеку
/// с экрана**, — просто ни разу не записан применительно к голосу.
///
/// ```
/// WalkIntents.swift, голова WalkTagIntent
///     «Два разных действия на одной наклейке человек не разведёт:
///      у двери он не вспоминает, какое из них сейчас нужно»
/// DoorTagScreen.swift, карточка «без метки — то же самое»
///     «Голосом: „Togo: прогулка" — Siri поймёт и на часах»
///        ← это ОБЕЩАНИЕ ПОЛЬЗОВАТЕЛЮ, и оно называет ОДНУ фразу
/// ```
///
/// Второе — не комментарий, а текст экрана в пяти языках: продукт уже
/// говорит, что голосовой вход в прогулку один и двусторонний. Три
/// готовые фразы со словом «прогулка» на одну работу рисковали бы ровно
/// этим обещанием: Siri уводит близкую фразу к соседу, и «Togo: прогулка»
/// досталось бы «Начать прогулку».
///
/// **Чего это НЕ значит.** `StartWalkIntent` и `FinishWalkIntent`
/// никуда не делись и видны в «Командах» как действия — именно так
/// их и ставят на метку NFC (`DoorTagScreen`, шаг 4) и на кнопку
/// «Действие». **Готовая фраза и действие в «Командах» — два разных
/// вопроса**, и опись сложила их в один.
///
/// > **Решения Виктории про эти два интента в git нет.** Довод выше
/// > собран из кода и из текста экрана, а не из её слова, и записан
/// > здесь с адресами именно поэтому: чтобы следующий спорил с доводом,
/// > а не открывал отсутствие заново. Цена ошибки в каждую сторону:
/// > добавить — риск увести обещанную фразу, снять обещание нечем
/// > (оно уже в пяти локалях); не добавлять — человек, сказавший
/// > «Того, закончить прогулку», не получит ничего, пока не соберёт
/// > команду руками.
///
/// > **ГРАНИЦА ЗАМЕРА, и она проходит посреди довода выше.** Измерено
/// > две вещи, обе читаются в git: интентов в дереве **восемь**, готовых
/// > фраз **пять** (опись звала это «5 из 7» — семи интентов нет,
/// > `WalkMarkIntent` она не считала вовсе); и обещание «одна фраза»
/// > стоит на экране в **пяти** локалях
/// > (`DoorTagScreen.swift:57`, ключ ««Togo: прогулка» — Siri поймёт
/// > и на часах.»). **Не измерено — то, КАК Siri разводит близкие
/// > фразы.** «Уводит к соседу» — правдоподобный механизм, а не наш
/// > замер: Siri внешняя система, из прогона недостижимая, и телефона
/// > под этот вопрос никто не брал. Значит решение держится
/// > на обещании с экрана, а не на поведении Siri; опровергнуть его
/// > можно только телефоном, и опровержение будет стоить правки
/// > текста в пяти локалях.
///
/// Список исключений ниже — **не проза**: на нём стоит
/// `ГотовыеФразыTests`, и девятый интент без записи в одном из двух
/// мест красит прогон.
struct TogoShortcuts: AppShortcutsProvider {
    /// Интенты, которым готовая фраза НЕ даётся, и причина у каждого.
    ///
    /// Читается сторожем `ГотовыеФразыTests`, а не только человеком:
    /// он сверяет все объявленные в дереве интенты с этим словарём
    /// и с фразами ниже. Запись, пережившая свой интент, тоже красит —
    /// иначе под неё можно спрятать новый.
    ///
    /// внутреннее: причины читает сторож и разработчик, на экран
    /// и в «Команды» они не попадают — в каталог не идут нарочно.
    static let безГотовойФразы: [String: String] = [
        "StartWalkIntent": """
            Обе стороны прогулки голосом закрывает WalkTagIntent. \
            DoorTagScreen обещает человеку одну фразу «Togo: прогулка», \
            и вторая фраза про прогулку уводила бы её у Siri.
            """,
        "FinishWalkIntent": """
            То же, что у StartWalkIntent: WalkTagIntent заканчивает \
            идущую прогулку сам. В «Командах» действие доступно.
            """,
        "WalkMarkIntent": """
            LiveActivityIntent с параметром «что отметить»: работает \
            только при ИДУЩЕЙ прогулке и только кнопкой на живой \
            активности. Готовая фраза звала бы его вне прогулки \
            и отвечала бы отказом.
            """,
    ]

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
            intent: WalkTagIntent(),
            phrases: ["\(.applicationName): прогулка",
                      "Прогулка в \(.applicationName)"],
            shortTitle: "Прогулка",
            systemImageName: "figure.walk"
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
