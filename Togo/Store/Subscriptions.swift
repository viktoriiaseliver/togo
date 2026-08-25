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
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            lastError = "Не удалось загрузить подписки. Проверь соединение."
            log.error("StoreKit: \(error.localizedDescription)")
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "Покупка не прошла. Попробуй ещё раз."
            log.error("Покупка: \(error.localizedDescription)")
        }
    }

    /// Кнопка обязательна по правилам App Store и просто по-человечески нужна.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Не удалось восстановить покупки."
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
        ("pawprint.circle", "Вторая и следующие собаки", "переключатель наверху главного"),
        ("person.3", "Семья больше двух человек", "роли, дежурство, ссылка ситтера"),
        ("doc.text", "Отчёты врачу без ограничений", "CSV остаётся бесплатным"),
    ]

    /// Что перестанет работать после отключения подписки. Показывается
    /// до отмены, а не после: человек должен понимать, что теряет.
    static let lostOnDowngrade = [
        ("square.grid.3x3", "Матрица переноса навыка", "занятия и «не брал еду» останутся"),
        ("pawprint.circle", "Вторая и следующие собаки", "их записи сохранятся и вернутся при возобновлении"),
        ("person.3", "Семья больше двух человек", "лишние участники станут наблюдателями, никого не удалим"),
    ]

    static let freeForever = [
        "Окно натощак",
        "Защита от двойной дозы",
        "«Как попросил»",
        "«Не брал еду» в занятии",
        "Строка про наказание после лужи",
    ]
}
