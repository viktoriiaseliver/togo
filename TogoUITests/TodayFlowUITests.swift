import XCTest

/// Дымовые UI-тесты: проверяют не вёрстку, а то, что путь от главного экрана
/// к записи вообще проходится и что обещания продукта видны на экране.
nonisolated final class TodayFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
    }

    func testГлавныйЭкранПоказываетСобакуИКнопки() {
        XCTAssertTrue(app.staticTexts["Стич"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Просится"].firstMatch.exists, "«Просится» — главная кнопка, она всегда на месте")
        XCTAssertTrue(app.buttons["Гулять"].exists)
        XCTAssertTrue(app.buttons["Ещё"].exists)
    }

    func testЧетыреВкладкиБезЗдоровьяУЗдоровойСобаки() {
        XCTAssertTrue(app.tabBars.buttons["Сегодня"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["История"].exists)
        XCTAssertTrue(app.tabBars.buttons["Семья"].exists)
        XCTAssertTrue(app.tabBars.buttons["Стич"].exists,
                      "всё про собаку — своя вкладка, а не четыре уровня в шторке")
        XCTAssertFalse(app.tabBars.buttons["Здоровье"].exists,
                       "у здоровой собаки медицины на главном нет вовсе")
    }

    func testВердиктПредлагаетВывестиПервойКнопкой() {
        app.buttons["Просится"].firstMatch.tap()
        let вывожу = app.buttons["Вывожу"]
        XCTAssertTrue(вывожу.waitForExistence(timeout: 3),
                      "«Вывожу» стоит первой во всех четырёх исходах вердикта")
    }

    func testЗаписьЕдыПоявляетсяВЛенте() {
        app.buttons["Еда"].firstMatch.tap()
        let записать = app.buttons["Записать"]
        XCTAssertTrue(записать.waitForExistence(timeout: 3))
        записать.tap()
        XCTAssertTrue(app.buttons["Отменить"].waitForExistence(timeout: 3),
                      "каждая запись отменяется тостом")
    }

    func testНастройкиСодержатОбязательныеРазделы() {
        app.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))

        for раздел in ["Данные и приватность", "Политика конфиденциальности", "Условия использования"] {
            let элемент = app.descendants(matching: .any).matching(identifier: раздел).firstMatch
            if !элемент.exists { app.swipeUp() }
            XCTAssertTrue(элемент.waitForExistence(timeout: 3),
                          "\(раздел) — обязательный раздел для App Store")
        }
    }
}
