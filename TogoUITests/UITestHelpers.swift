import XCTest

/// Общий поиск по началу подписи с прокруткой.
///
/// Подписи в приложении составные («Профиль собаки, Стич»), поэтому точное
/// совпадение по идентификатору не годится, а копия этого метода жила
/// в трёх тестовых классах.
nonisolated extension XCTestCase {
    func найти(_ подпись: String, в app: XCUIApplication, попыток: Int = 6) -> XCUIElement {
        for попытка in 0..<попыток {
            let элемент = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", подпись))
                .firstMatch
            if элемент.exists && элемент.isHittable { return элемент }
            if попытка < попыток - 1 { app.swipeUp() }
        }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", подпись))
            .firstMatch
    }
}
