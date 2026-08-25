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


    private func открытьЗапас() {
        app.buttons["Ещё"].firstMatch.tap()
        найти("Профиль собаки", в: app).tap()
        найти("Питание и режим", в: app).tap()
        _ = app.navigationBars["Питание"].waitForExistence(timeout: 5)
        найти("Записать корм", в: app).tap()
        _ = app.navigationBars["Запас корма"].waitForExistence(timeout: 5)
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
