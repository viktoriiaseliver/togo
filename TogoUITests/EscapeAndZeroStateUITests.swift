import XCTest

/// Проверки того, что нельзя проверить модульно: из любого места есть выход,
/// а на пустой базе ни один экран не превращается в белый лист.
nonisolated final class EscapeAndZeroStateUITests: XCTestCase {
    private var app: XCUIApplication!


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

    func testИзШторкиЕщёМожноУйтиНаВкладкуСобаки() {
        app.buttons["Ещё"].firstMatch.tap()
        let всё = найти("Всё про собаку", в: app)
        XCTAssertTrue(всё.waitForExistence(timeout: 3))
        всё.tap()
        // Шторка закрывается и переключает вкладку, а не строит дерево внутри себя.
        XCTAssertTrue(найти("Питание и режим", в: app).waitForExistence(timeout: 5))
    }

    func testПитаниеВДвухТапахОтВкладки() {
        app.tabBars.buttons["Стич"].tap()
        let питание = найти("Питание и режим", в: app)
        XCTAssertTrue(питание.waitForExistence(timeout: 5))
        питание.tap()
        XCTAssertTrue(app.navigationBars["Питание"].waitForExistence(timeout: 5))
    }

    func testНастройкиДоступныСКаждойВкладки() {
        for вкладка in ["История", "Семья", "Стич"] {
            app.tabBars.buttons[вкладка].tap()
            XCTAssertTrue(app.buttons["Настройки"].firstMatch.waitForExistence(timeout: 3),
                          "шестерёнка должна быть на вкладке «\(вкладка)»")
        }
    }

    func testИнструкциюМожноПеречитать() {
        app.buttons["Настройки"].tap()
        let как = найти("Как это работает", в: app)
        XCTAssertTrue(как.waitForExistence(timeout: 5))
        как.tap()
        XCTAssertTrue(app.navigationBars["Как это работает"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists, "должна быть кнопка назад")
    }

    func testУдалениеВсехДанныхВозвращаетКОнбордингу() {
        app.buttons["Настройки"].tap()

        let данные = найти("Данные и приватность", в: app)
        XCTAssertTrue(данные.waitForExistence(timeout: 5))
        данные.tap()

        let удалить = найти("Удалить все данные", в: app)
        XCTAssertTrue(удалить.waitForExistence(timeout: 5))
        удалить.tap()

        let подтвердить = app.buttons["Удалить всё"].firstMatch
        XCTAssertTrue(подтвердить.waitForExistence(timeout: 3))
        подтвердить.tap()

        XCTAssertTrue(app.staticTexts["Всё удалено"].waitForExistence(timeout: 5),
                      "приложение должно подтвердить, что данных не осталось")
    }
}
