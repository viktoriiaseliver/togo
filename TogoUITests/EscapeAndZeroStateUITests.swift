import XCTest

/// Проверки того, что нельзя проверить модульно: из любого места есть выход,
/// а на пустой базе ни один экран не превращается в белый лист.
nonisolated final class EscapeAndZeroStateUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Ищет элемент по началу подписи и при необходимости доскроллит до него.
    /// Подписи в приложении составные («Профиль собаки, Стич»), поэтому
    /// точное совпадение по идентификатору здесь не годится.
    private func найти(_ подпись: String, попыток: Int = 6) -> XCUIElement {
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

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        _ = app.staticTexts["Стич"].waitForExistence(timeout: 10)
    }

    func testУКаждойШторкиЕстьКрестик() {
        for кнопка in ["Просится", "Стул", "Еда", "Инцидент"] {
            app.buttons[кнопка].firstMatch.tap()
            let закрыть = app.buttons["Закрыть"].firstMatch
            XCTAssertTrue(закрыть.waitForExistence(timeout: 3),
                          "у шторки «\(кнопка)» нет явной кнопки закрытия")
            закрыть.tap()
            XCTAssertTrue(app.buttons["Просится"].firstMatch.waitForExistence(timeout: 3),
                          "после закрытия «\(кнопка)» не вернулись на главный")
        }
    }

    func testИзШторкиЕщёОткрываетсяПрофиль() {
        app.buttons["Ещё"].firstMatch.tap()
        let профиль = найти("Профиль собаки")
        XCTAssertTrue(профиль.waitForExistence(timeout: 3))
        профиль.tap()
        XCTAssertTrue(найти("Питание и режим").waitForExistence(timeout: 5),
                      "переход в профиль из шторки должен работать, а не быть мёртвой ссылкой")
    }

    func testПитаниеДоступноИзПрофиля() {
        app.buttons["Ещё"].firstMatch.tap()
        найти("Профиль собаки").tap()
        let питание = найти("Питание и режим")
        XCTAssertTrue(питание.waitForExistence(timeout: 5))
        питание.tap()
        XCTAssertTrue(app.navigationBars["Питание"].waitForExistence(timeout: 5))
    }

    func testИнструкциюМожноПеречитать() {
        app.buttons["Настройки"].tap()
        let как = найти("Как это работает")
        XCTAssertTrue(как.waitForExistence(timeout: 5))
        как.tap()
        XCTAssertTrue(app.navigationBars["Как это работает"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists, "должна быть кнопка назад")
    }

    func testУдалениеВсехДанныхВозвращаетКОнбордингу() {
        app.buttons["Настройки"].tap()

        let данные = найти("Данные и приватность")
        XCTAssertTrue(данные.waitForExistence(timeout: 5))
        данные.tap()

        let удалить = найти("Удалить все данные")
        XCTAssertTrue(удалить.waitForExistence(timeout: 5))
        удалить.tap()

        let подтвердить = app.buttons["Удалить всё"].firstMatch
        XCTAssertTrue(подтвердить.waitForExistence(timeout: 3))
        подтвердить.tap()

        XCTAssertTrue(app.staticTexts["Всё удалено"].waitForExistence(timeout: 5),
                      "приложение должно подтвердить, что данных не осталось")
    }
}
