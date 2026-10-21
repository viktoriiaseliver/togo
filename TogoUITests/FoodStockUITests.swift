import XCTest

/// Проверка того, что человек и увидел: добавил корм — а на экране ничего
/// не изменилось. Причина была в том, что список читал связь собаки,
/// которую SwiftData ещё не применил.
nonisolated final class FoodStockUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        _ = app.staticTexts["Стич"].waitForExistence(timeout: 10)
    }


    /// Два тапа от вкладки вместо четырёх уровней внутри шторки.
    ///
    /// **Переходы проверяются, а не ожидаются молча** — замер 21.10.2026.
    /// Здесь стояло `_ = app.navigationBars["Запас корма"]
    /// .waitForExistence(timeout: 5)`: результат выбрасывался, а экран
    /// с таким заголовком не существует с 26.08.2026 (`9ed830b`
    /// переименовал его в «Чем кормим»). Из-за этого отказ уезжал
    /// на строки ниже и читался как «нет кнопки „Добавить корм"»,
    /// хотя сломан был ПЕРЕХОД: `FoodStockScreen` не рисовался ни разу.
    ///
    /// > Проигнорированное ожидание не ускоряет тест — оно переносит
    /// > его отказ в другое место и переодевает в чужую причину.
    private func открытьЗапас() {
        app.tabBars.buttons["Стич"].tap()
        найти("Питание и режим", в: app).tap()
        XCTAssertTrue(app.navigationBars["Питание"].waitForExistence(timeout: 5),
                      "вкладка собаки не открыла «Питание» — дальше смотреть нечего")
        найти("Записать корм", в: app).tap()
        XCTAssertTrue(app.navigationBars["Чем кормим"].waitForExistence(timeout: 5),
                      "переход на запас корма не состоялся: экран зовётся «Чем кормим» с 26.08.2026")
    }

    func testДобавленныйКормПоявляетсяВСписке() {
        открытьЗапас()

        найти("Добавить корм", в: app).tap()
        let добавить = app.buttons["Добавить"].firstMatch
        XCTAssertTrue(добавить.waitForExistence(timeout: 5))
        добавить.tap()

        // Именно это и не работало: список оставался пустым.
        XCTAssertTrue(найти("Сухой", в: app).waitForExistence(timeout: 5),
                      "добавленный корм должен появиться в списке сразу")
        XCTAssertFalse(app.staticTexts["Корм пока не записан"].exists,
                       "пустое состояние должно уйти")
    }

    func testКормМожноОткрытьИПоправить() {
        открытьЗапас()
        найти("Добавить корм", в: app).tap()
        app.buttons["Добавить"].firstMatch.tap()
        _ = найти("Сухой", в: app).waitForExistence(timeout: 5)

        найти("Сухой", в: app).tap()
        XCTAssertTrue(app.buttons["Сохранить"].firstMatch.waitForExistence(timeout: 5),
                      "корм должен открываться на правку")
        XCTAssertTrue(app.buttons["Убрать корм"].firstMatch.exists,
                      "и его должно быть можно убрать")
    }

    func testВлажныйКормПредупреждаетПроВоду() {
        открытьЗапас()
        найти("Добавить корм", в: app).tap()
        _ = app.buttons["Добавить"].firstMatch.waitForExistence(timeout: 5)

        app.buttons["Влажный"].firstMatch.tap()
        let предупреждение = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'вода'")
        ).firstMatch
        XCTAssertTrue(предупреждение.waitForExistence(timeout: 3),
                      "граммы сухого и влажного не равны — об этом надо сказать")
    }
}
