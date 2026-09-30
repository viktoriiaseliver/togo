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
        #endif
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        // Права спрашиваем сразу при запуске, а не когда откроют пейволл.
        //
        // До 30.09 `refreshEntitlements` звали только `load()` (он живёт
        // на пейволле), восстановление и приход транзакции. То есть
        // у подписчика `isPro` оставался `false`, пока он сам не открывал
        // экран покупки, — и замок на второй собаке, на матрице и на
        // приглашении третьего стоял у того, кто уже заплатил.
        Task { [weak self] in await self?.refreshEntitlements() }
    }

    /// Можно ли завести ещё одну собаку.
    ///
    /// Одна дверь на все пути: «Добавить собаку» в настройках, «Завести
    /// ещё собаку» на вкладке «Собака» и список собак. До 30.09 проверка
    /// стояла только в настройках, а два других пути вели в редактор
    /// без неё — вторую собаку заводили без подписки.
    func canAddDog(existing count: Int) -> Bool {
        count == 0 || isPro
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
            lastError = "Не удалось загрузить подписки. Проверь соединение."
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
            lastError = "Покупка не прошла. Попробуй ещё раз."
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
        /// Спросить не вышло — текст в `lastError`.
        case failed
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
            lastError = "Не удалось восстановить покупки. Проверь связь и попробуй ещё раз."
            lastRestore = .failed
            log.error("Восстановление: \(error.localizedDescription)")
            UsageLog.note(.purchase, "restored", outcome: .failed)
        }
    }

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
    static let proFeatures = [
        ("square.grid.3x3", "Матрица переноса навыка", "кто просит × где просят × что вокруг"),
        ("pawprint.circle", "Вторая и следующие собаки", "переключатель на вкладке «Собака»"),
        // «Ссылка ситтера» стояла здесь до 22.09 — такой ссылки в коде нет
        // (`grep` по `sitterLink`/`sitterToken` пуст), а инструкция ситтеру
        // есть и работает. Продавать несуществующее — тот же 3.1.2, из-за
        // которого отсюда уже убирали «Отчёты врачу без ограничений».
        // Подпись была «роли, дежурство, инструкция ситтеру» — а всё это
        // работает и без подписки, у семьи из двух. Закрыт только третий
        // участник (`FamilyScreen`, кнопка «Добавить человека»).
        ("person.3", "Семья больше двух человек", "третий и следующие участники"),
    ]
    // «Отчёты врачу без ограничений» из списка убраны: ограничений нет
    // нигде в коде (isPro не проверяется ни в Health, ни в Exporter), а
    // продавать то, что и так бесплатно, — обман и риск по 3.1.2.

    /// Что перестанет работать после отключения подписки. Показывается
    /// до отмены, а не после: человек должен понимать, что теряет.
    ///
    /// **Третья строка правлена 28.09, и правлена по замеру.** Она
    /// обещала «лишние участники станут наблюдателями», а понижения
    /// ролей в дереве нет **нигде**: `FamilyScreen` («Добавить человека») закрывает только
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
    ///
    /// **Вторая строка исполняется кодом с 30.09.** До этого после
    /// окончания подписки вторая собака продолжала работать целиком:
    /// переключатель и `activeDog` на `isPro` не смотрели. Теперь без Pro
    /// открыта только первая заведённая (`AppState.закрыта`), остальные
    /// видны с замком и ведут на пейволл, а записи не трогаются.
    static let lostOnDowngrade = [
        ("square.grid.3x3", "Матрица переноса навыка", "оси «где» и «кто просит» останутся; закроется карточка «следующий шаг»"),
        ("pawprint.circle", "Вторая и следующие собаки", "открыта останется первая заведённая; записи остальных сохранятся и вернутся с подпиской"),
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
