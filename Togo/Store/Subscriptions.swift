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
        ("person.3", "Семья больше двух человек", "роли, дежурство, инструкция ситтеру"),
    ]
    // «Отчёты врачу без ограничений» из списка убраны: ограничений нет
    // нигде в коде (isPro не проверяется ни в Health, ни в Exporter), а
    // продавать то, что и так бесплатно, — обман и риск по 3.1.2.

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
