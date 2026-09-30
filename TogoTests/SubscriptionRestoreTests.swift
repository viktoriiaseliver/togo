import Testing
import Foundation
import StoreKit
@testable import Togo

/// Сторож на разбор отказа восстановления (`SubscriptionStore.outcome(for:)`).
///
/// **Повод — одна запись журнала действий с телефона Виктории.** За девять
/// дней ровно один `purchase · restored · failed`, 28.09 в 13:49:56.
/// Ответить по нему, сломана ли кнопка, оказалось нельзя: `AppStore.sync()`
/// бросает восемь разных `StoreKitError`, и среди них `userCancelled` —
/// человек, закрывший окно входа в App Store. Общий `catch` писал на все
/// восемь одно слово `failed` и один текст «проверь связь».
///
/// Проверки **от обратного**, потому что отрицательное утверждение
/// выполняется и при отсутствии предмета: «отмена не попадает в failed»
/// было бы истинно и у разбора, который не возвращает ничего. Поэтому
/// каждый случай требует **именно свой** исход, а не «не тот».
///
/// **Граница этого файла, чтобы её не пришлось выводить заново.** Он
/// проверяет разбор броска в исход и различимость текстов. Он НЕ
/// проверяет, что `AppStore.sync()` бросает именно это: набор случаев
/// прочитан в `iPhoneOS27.0.sdk`, а не измерен на живом магазине, и
/// локальная конфигурация StoreKit под `xcodebuild` в этом проекте
/// не подхватывается (замер соседнего проекта 23.09). Сюда же: текст
/// он сверяет между собой, а не с экраном — что человек увидит,
/// отвечает кадр.
@Suite("Восстановление покупок: разбор причины отказа")
struct SubscriptionRestoreTests {

    /// Первой — проверка, что набору было что проверять.
    ///
    /// Без неё остальные молчали бы так же, как набор, у которого всё
    /// хорошо: перечисление, из которого убрали случаи, даёт зелёный
    /// прогон на любом количестве проверок по нему.
    @Test("Причин отказа четыре, и все они различимы")
    func переченьНаполнен() {
        let все = SubscriptionStore.RestoreFailure.allCases
        #expect(все.count == 4)
        #expect(Set(все.map(\.rawValue)).count == все.count)
    }

    @Test("Закрытое окно входа — отмена, а не отказ")
    func отменаНеОтказ() {
        #expect(SubscriptionStore.outcome(for: StoreKitError.userCancelled) == .cancelled)
    }

    @Test("Нет связи — своя причина")
    func сеть() {
        let ошибка = StoreKitError.networkError(URLError(.notConnectedToInternet))
        #expect(SubscriptionStore.outcome(for: ошибка) == .failed(.network))
    }

    @Test("Товара нет в магазине страны — своя причина")
    func витринаСтраны() {
        #expect(SubscriptionStore.outcome(for: StoreKitError.notAvailableInStorefront)
                == .failed(.storefront))
    }

    @Test("Спрашивать не вправе сама сборка — своя причина")
    func правУСборкиНет() {
        #expect(SubscriptionStore.outcome(for: StoreKitError.notEntitled)
                == .failed(.notEntitled))
    }

    @Test("Сбой магазина и неизвестное — общая причина, и она названа")
    func системное() {
        #expect(SubscriptionStore.outcome(for: StoreKitError.unknown) == .failed(.system))
        #expect(SubscriptionStore.outcome(for: StoreKitError.systemError(URLError(.badURL)))
                == .failed(.system))
    }

    /// Не `StoreKitError` вовсе — тоже `system`, а не падение и не отмена.
    ///
    /// Важно именно «не отмена»: отмена молчит на экране, и чужая ошибка,
    /// попавшая в неё, сделала бы отказ невидимым.
    @Test("Чужая ошибка не притворяется отменой")
    func чужаяОшибка() {
        struct Своя: Error {}
        #expect(SubscriptionStore.outcome(for: Своя()) == .failed(.system))
    }

    /// Тот самый дефект, ради которого всё заведено: один текст
    /// на несколько причин даёт совет, неверный для большинства из них.
    @Test("У каждой причины свой текст, и ни один не пуст")
    func текстыРазные() {
        let тексты = SubscriptionStore.RestoreFailure.allCases.map(\.message)
        #expect(тексты.allSatisfy { !$0.isEmpty })
        #expect(Set(тексты).count == тексты.count)
    }

    /// «Проверь связь» — совет, и он верен ровно там, где связь при чём.
    ///
    /// Проверка стоит от обратного: она требует, чтобы совет **был**
    /// у сетевой причины и **не было** у остальных трёх. Формулировка
    /// «совет не у всех» выполнялась бы и при отсутствии его вовсе.
    @Test("Совет про связь стоит только там, где помогает")
    func советТамГдеПомогает() {
        #expect(SubscriptionStore.RestoreFailure.network.message.contains("связь"))
        for причина in SubscriptionStore.RestoreFailure.allCases where причина != .network {
            #expect(!причина.message.contains("связь"),
                    "«\(причина.rawValue)» советует проверить связь, а связь тут ни при чём")
        }
    }

    /// Причина обязана доезжать до журнала: ради этого она и заведена.
    @Test("В журнал уезжает причина, а не общее слово")
    func причинаВЖурнале() {
        let следы = SubscriptionStore.RestoreFailure.allCases.map(\.detail)
        #expect(Set(следы).count == следы.count)
        #expect(следы.allSatisfy { $0.hasPrefix("restored-") })
        #expect(!следы.contains("restored"))
    }
}
