import XCTest

/// Снимки при самом крупном системном шрифте.
///
/// Здесь ловится то, что не видно на обычном размере: обрезанные подписи,
/// колонки, схлопнувшиеся в щель, кнопки, у которых текст не помещается.
/// Автоматически такое не проверить — снимки смотрят глазами.
nonisolated final class DynamicTypeScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXL",
        ]
        app.launch()
        _ = app.staticTexts["Стич"].waitForExistence(timeout: 10)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testXL01Сегодня() {
        capture("xl-01-today")
        app.swipeUp()
        capture("xl-01-today-scrolled")
    }

    func testXL02Просится() {
        app.buttons["Просится"].firstMatch.tap()
        _ = app.buttons["Вывожу"].waitForExistence(timeout: 5)
        capture("xl-02-needs")
    }

    func testXL03Настройки() {
        app.buttons["Настройки"].tap()
        _ = app.navigationBars["Настройки"].waitForExistence(timeout: 5)
        capture("xl-03-settings")
    }

    func testXL04Семья() {
        app.tabBars.buttons["Семья"].tap()
        _ = app.navigationBars["Семья"].waitForExistence(timeout: 5)
        capture("xl-04-family")
        let первый = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Виктория"))
            .firstMatch
        if первый.waitForExistence(timeout: 3) {
            первый.tap()
            capture("xl-05-permissions")
        }
    }
}
