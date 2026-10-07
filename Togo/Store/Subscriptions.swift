import Foundation
import StoreKit
import Observation

/// Того Pro. Что продаётся, а что нет — вопрос этики, а не выручки.
///
/// Бесплатно навсегда: окно натощак, защита от двойной дозы, «как попросил»,
/// «не брал еду» и строка про наказание. Без них приложение молча вредит
/// собаке, поэтому они не продаются.
@Observable
final class SubscriptionStore {
    enum ProductID {
        static let monthly = "app.togo.diary.pro.monthly"
        static let yearly = "app.togo.diary.pro.yearly"
        static let all = [monthly, yearly]
    }

    private(set) var products: [Product] = []
    private(set) var entitled = false

    #if DEBUG
    /// Проверять надо оба состояния — и с подпиской, и без. В отладочной
    /// сборке её можно включить и выключить руками, не покупая ничего.
    var debugOverride: Bool? {
        didSet { UserDefaults.standard.set(debugOverride, forKey: "debug.pro") }
    }

    var isPro: Bool { debugOverride ?? entitled }
    #else
    var isPro: Bool { entitled }
    #endif

    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Слушатель транзакций живёт столько же, сколько приложение: магазин
    /// создаётся один раз в `TogoApp` и не пересоздаётся. Поэтому задачу
    /// намеренно никто не отменяет — отменять её было бы нечем и незачем.
    private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        debugOverride = UserDefaults.standard.object(forKey: "debug.pro") as? Bool
        применитьОтладочныйИсходВосстановления()
        #endif
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    /// Что ответил магазин в последний раз. Нужно затем, что «пусто»
    /// и «ошибка» — разные ответы, а выглядели одинаково.
    ///
    /// 23.09 тестировщик написал «Цен нет». Экран показывал «Цены
    /// не загрузились · обычно это связь» — и это была догадка
    /// приложения, а не то, что случилось: `Product.products` вернул
    /// пустой список БЕЗ ошибки, то есть связь была, а продуктов магазин
    /// не дал. Сорок четвёртое молчание того же рода, что сорок три
    /// сохранения.
    enum Ответ: Equatable, Sendable {
        case неСпрашивали
        case пусто
        case частично(получено: Int, просили: Int)
        case всё
        case ошибка(String)
    }

    private(set) var ответМагазина: Ответ = .неСпрашивали

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = loaded.sorted { $0.price < $1.price }
            if loaded.isEmpty {
                ответМагазина = .пусто
                // Не ошибка связи: магазин ответил и не дал ничего.
                //
                // Замер 23.09: причина оказалась одна и вне кода — у Виктории
                // не подписано Соглашение о платных приложениях («Новое»
                // в ASC → Бизнес → Соглашения). Пока оно не подписано,
                // `Product.products` возвращает пустой список ВСЕГДА, при
                // любом состоянии продуктов и в любой сборке. Один
                // неподписанный документ держал покупки в трёх приложениях,
                // а искали его в коде весь день.
                lastError = nil
                log.error("StoreKit: магазин ответил пустым списком на \(ProductID.all.count) идентификатора")
                UsageLog.note(.open, "paywall-empty", on: .paywall, outcome: .failed)
            } else if loaded.count < ProductID.all.count {
                ответМагазина = .частично(получено: loaded.count, просили: ProductID.all.count)
                let пришли = Set(loaded.map(\.id))
                let нет = ProductID.all.filter { !пришли.contains($0) }
                log.error("StoreKit: не пришли продукты \(нет.joined(separator: ", "))")
                UsageLog.note(.open, "paywall-partial", on: .paywall, outcome: .failed)
            } else {
                ответМагазина = .всё
                lastError = nil
            }
        } catch {
            ответМагазина = .ошибка(error.localizedDescription)
            // `String(localized:)`, а не литерал: `lastError` объявлен
            // `String?`, и присвоенный ему литерал рисуется дословно мимо
            // каталога. Перевод этих трёх строк лежал в каталоге готовым
            // и не доезжал до экрана ни разу — тот же класс, что 321
            // строка, починенная 28.09 (`d701bd7`).
            lastError = String(localized: "Не удалось загрузить подписки. Проверь соединение.")
            log.error("StoreKit: \(error.localizedDescription)")
            UsageLog.note(.open, "paywall-error", on: .paywall, outcome: .failed)
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                UsageLog.note(.purchase, "bought", on: .paywall)
                await handle(verification)
            case .userCancelled:
                UsageLog.note(.purchase, "bought", on: .paywall, outcome: .cancelled)
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = String(localized: "Покупка не прошла. Попробуй ещё раз.")
            log.error("Покупка: \(error.localizedDescription)")
            UsageLog.note(.purchase, "bought", on: .paywall, outcome: .failed)
        }
    }

    /// Чем кончилось восстановление.
    ///
    /// Нужно ровно затем, чтобы кнопка не молчала. Раньше успех и «покупок
    /// нет» выглядели одинаково — никак: `entitled` оставался `false`,
    /// экран не менялся, и человек читал это как «кнопка не нажимается».
    /// Именно так и написал тестер 22.09.
    enum Restore: Equatable {
        /// Подписка нашлась и включена.
        case restored
        /// Магазин ответил, покупок на этом Apple ID нет.
        case nothingFound
        /// Человек закрыл окно входа в App Store. **Не отказ**, и потому
        /// стоит отдельно от `failed`: см. `RestoreFailure`.
        case cancelled
        /// Спросить не вышло. Причина названа, текст в `lastError`.
        case failed(RestoreFailure)
    }

    /// Почему `AppStore.sync()` не довёл восстановление до ответа.
    ///
    /// **Заведено 30.09 из одной записи журнала.** За девять дней на
    /// телефонах случился ровно один `purchase · restored · failed`
    /// (28.09, 13:49:56). Ответить по нему, сломана ли кнопка, оказалось
    /// нельзя: `AppStore.sync()` бросает **восемь** разных `StoreKitError`
    /// — `unknown`, `userCancelled`, `networkError`, `systemError`,
    /// `notAvailableInStorefront`, `notEntitled`, `unsupported`,
    /// `invalidPresentationContext` (прочитано в `iPhoneOS27.0.sdk`), —
    /// а общий `catch` писал на все восемь одно слово `failed` и один
    /// текст «проверь связь».
    ///
    /// **Среди восьми есть отмена человеком.** `sync()` показывает окно
    /// входа в App Store, и закрывший его даёт ту же запись, что упавший
    /// магазин. То есть журнал не различал «сломалось» и «передумал»,
    /// а экран отвечал закрывшему окно, что у него проблемы со связью.
    ///
    /// Форма отказа у соседа другая, и потому у него это было верно
    /// с самого начала: `product.purchase()` возвращает отмену **случаем
    /// результата** (`purchase()` выше, `.userCancelled`), а `sync()`
    /// сообщает о ней **броском**. Разница не в решении автора,
    /// а в устройстве двух API.
    ///
    /// Причина уезжает в `detail` журнала, чтобы следующий такой отказ
    /// отвечал на вопрос сам, а не требовал второго захода.
    enum RestoreFailure: String, Equatable, Sendable, CaseIterable {
        /// Связи не было.
        case network
        /// Подписки Togo нет в App Store его страны.
        case storefront
        /// Спрашивать магазин не вправе сама сборка — не человек.
        case notEntitled
        /// Всё остальное, включая случаи новее нашей цели развёртывания.
        case system

        /// Как причина называется в журнале действий.
        ///
        /// Словарь закрытый: свободный текст человека в `detail`
        /// не попадает никогда (`UsageLog.note`).
        var detail: String { "restored-" + rawValue }

        /// Что сказать человеку.
        ///
        /// Совет здесь стоит только там, где он помогает. «Проверь связь»
        /// верно для одной причины из четырёх, и раздать его всем — это
        /// уже разобранный у нас класс: сообщение, покрывающее несколько
        /// причин одним текстом, даёт совет, неверный для большинства.
        /// Хуже молчания: молчание заставляет спросить, неверный совет —
        /// попробовать и увериться.
        var message: String {
            switch self {
            case .network:
                String(localized: "Не удалось восстановить покупки. Проверь связь и попробуй ещё раз.")
            case .storefront:
                String(localized: "В App Store твоей страны подписки Togo нет. Дело не в твоём Apple ID.")
            case .notEntitled:
                String(localized: "Дело не в твоих настройках: приложению не разрешено спрашивать App Store. Напиши нам.")
            case .system:
                String(localized: "App Store не ответил. Попробуй ещё раз позже.")
            }
        }
    }

    /// Разбор броска в исход. Чистая функция: её можно спросить из теста,
    /// не поднимая ни магазина, ни экрана.
    ///
    /// `default` здесь не лень, а цель развёртывания: `unsupported`
    /// (iOS 18.4) и `invalidPresentationContext` (iOS 27) на iOS 17
    /// не сматчить без `#available`, и оба честно ложатся в `system`.
    /// Не `StoreKitError` — тоже `system`: своей ветки он не заслуживает,
    /// сказать о нём человеку нечего.
    static func outcome(for error: Error) -> Restore {
        guard let storeKit = error as? StoreKitError else { return .failed(.system) }
        switch storeKit {
        case .userCancelled: return .cancelled
        case .networkError: return .failed(.network)
        case .notAvailableInStorefront: return .failed(.storefront)
        case .notEntitled: return .failed(.notEntitled)
        case .systemError, .unknown: return .failed(.system)
        default: return .failed(.system)
        }
    }

    private(set) var isRestoring = false
    private(set) var lastRestore: Restore?

    /// Кнопка обязательна по правилам App Store и просто по-человечески нужна.
    ///
    /// Экран в журнал не передаём: `UsageLog` подставит текущий сам.
    /// Раньше здесь стоял жёсткий `.paywall`, и восстановление из настроек
    /// записывалось как пейволл — журнал врал о том, где человек стоял.
    func restore() async {
        // 22.09 журнал действий поймал шесть «restored» в одну секунду,
        // все с отказом: кнопка ничего не показывала, и человек жал ещё.
        // Второй заход отмечаем и не начинаем — иначе шесть обращений
        // к магазину вместо одного.
        guard !isRestoring else {
            UsageLog.note(.purchase, "restored", outcome: .duplicate)
            return
        }
        isRestoring = true
        lastRestore = nil
        lastError = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastRestore = entitled ? .restored : .nothingFound
            UsageLog.note(.purchase, "restored", outcome: entitled ? .done : .empty)
        } catch {
            let исход = Self.outcome(for: error)
            lastRestore = исход
            log.error("Восстановление: \(error.localizedDescription)")
            switch исход {
            case .cancelled:
                // Окно закрыл человек. Экрану сказать нечего: он и так
                // видел, как окно ушло, — ровно как у покупки выше.
                lastError = nil
                UsageLog.note(.purchase, "restored", outcome: .cancelled)
            case .failed(let причина):
                lastError = причина.message
                UsageLog.note(.purchase, причина.detail, outcome: .failed)
            case .restored, .nothingFound:
                // `outcome(for:)` их не возвращает: они приходят из `do`,
                // а не из броска. Ветка стоит, чтобы добавленный случай
                // не прошёл молча.
                break
            }
        }
    }

    #if DEBUG
    /// Поставить исход восстановления по аргументу запуска: `-Восстановление
    /// storefront`. Только отладочная сборка.
    ///
    /// **Заведено потому, что иначе эту поверхность не снять кадром.**
    /// Живого отказа магазина в симуляторе не добиться: локальная
    /// конфигурация StoreKit под `xcodebuild` не подхватывается, симулятор
    /// идёт в песочницу живого магазина. То есть тексты, которые человек
    /// читает в худшую свою минуту, не видел глазами никто — ровно тот
    /// случай, про который у нас записано: поверхность без кадра не
    /// «непроверенная», а «непроверяемая», и лечится она входом,
    /// а не старанием.
    ///
    /// Незнакомое имя **валит запуск нарочно**, как и у `-Сценарий`: молча
    /// подставить «ничего не случилось» значит дать тесту снять не то
    /// состояние и назвать это успехом.
    private func применитьОтладочныйИсходВосстановления() {
        let args = ProcessInfo.processInfo.arguments
        guard let место = args.firstIndex(of: "-Восстановление") else { return }
        let имя = args.indices.contains(место + 1) ? args[место + 1] : ""
        if имя == "cancelled" {
            lastRestore = .cancelled
            lastError = nil
            return
        }
        guard let причина = RestoreFailure(rawValue: имя) else {
            fatalError("неизвестный исход восстановления: «\(имя)»")
        }
        lastRestore = .failed(причина)
        lastError = причина.message
    }
    #endif

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        entitled = active
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// Что именно закрыто. Список короткий и честный.
    /// Подписи для пейволла — **выводятся из `ProFeature`**, а не лежат
    /// списком здесь.
    ///
    /// Прежде здесь стоял литерал из трёх кортежей, и он был
    /// единственным местом, где три вещи Pro перечислены. Ворота на него
    /// опереться не могли: ключа у кортежа нет, и `isPro` стоял по вью
    /// россыпью. Значит «Pro открывает ровно три вещи» было
    /// утверждением, которое нечем проверить, — а подпись и ворота
    /// могли разойтись молча, оба зелёные, каждый про своё.
    ///
    /// Форма отдачи та же (значок, название, пояснение), чтобы
    /// `PaywallScreen` не правился вовсе: у правки, меняющей то, что
    /// человек читает, приёмка — кадр, а здесь читаемое не меняется
    /// ни на символ.
    ///
    /// **Что сюда дописывать нельзя и почему — таблицей
    /// в `docs/design-handoff/DECISIONS.md`**, раздел про Pro. Там
    /// записано, какое обещание убирали трижды (отчёты врачу, ссылка
    /// ситтера, «ситтер со сроком») и что должно появиться в коде,
    /// чтобы вернуть каждое. Причина живёт там, а не комментарием
    /// здесь, ровно потому, что в третий раз обещание вернулось
    /// **через макет**: макет не читает комментарии Swift.
    static var proFeatures: [(String, String, String)] {
        ProFeature.allCases.map {
            let п = $0.подпись
            return (п.значок, п.название, п.пояснение)
        }
    }

    /// Что перестанет работать после отключения подписки. Показывается
    /// до отмены, а не после: человек должен понимать, что теряет.
    ///
    /// **Третья строка правлена 28.09, и правлена по замеру.** Она
    /// обещала «лишние участники станут наблюдателями», а понижения
    /// ролей в дереве нет **нигде**: `FamilyScreen:54` закрывает только
    /// ПРИГЛАШЕНИЕ третьего, а те, кто уже в семье, остаются с полными
    /// правами — писать, править, отмечать дозы.
    ///
    /// Обещание без исполнителя. Ошибка была в пользу человека — он
    /// получал больше обещанного, — и потому незаметная: никто
    /// не жалуется на то, что у него не отняли.
    ///
    /// **Выбран текст, а не код, и вот почему.** Понизить участника
    /// до наблюдателя — это отнять право у ЖИВОГО человека за чужую
    /// отмену подписки. В дневнике на семью, где дозы дают по очереди,
    /// это значит, что двое из четверых перестанут их отмечать —
    /// и узнают об этом в тот момент, когда собаке нужна таблетка.
    /// Такое решение стоит принимать явно, а не дописывать кодом
    /// под уже написанную строку.
    static let lostOnDowngrade = [
        ("square.grid.3x3", "Матрица переноса навыка", "занятия и «не брал еду» останутся"),
        ("pawprint.circle", "Вторая и следующие собаки", "их записи сохранятся и вернутся при возобновлении"),
        ("person.3", "Приглашать третьего человека", "те, кто уже в семье, остаются с прежними правами"),
    ]

    static let freeForever = [
        "Окно натощак",
        "Защита от двойной дозы",
        "«Как попросил»",
        "«Не брал еду» в занятии",
        "Строка про наказание после лужи",
    ]
}
