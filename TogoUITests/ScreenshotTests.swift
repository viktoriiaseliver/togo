import XCTest

/// Генератор скриншотов для App Store и для глазной проверки вёрстки.
///
/// Запуск:
///   xcodebuild ... test -only-testing:TogoUITests/ScreenshotTests \
///     -resultBundlePath build/Screens.xcresult
///   Tools/extract_screenshots.sh build/Screens.xcresult fastlane/screenshots
nonisolated final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        _ = app.staticTexts["Стич"].waitForExistence(timeout: 10)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test01Сегодня() {
        capture("01-today")
    }

    func test02Просится() {
        app.buttons["Просится"].firstMatch.tap()
        _ = app.buttons["Вывожу"].waitForExistence(timeout: 5)
        capture("02-needs-verdict")
    }

    func test03Стул() {
        app.buttons["Стул"].firstMatch.tap()
        _ = app.staticTexts["Колбаска"].waitForExistence(timeout: 5)
        capture("03-stool")
    }

    func test04Занятие() {
        app.buttons["Ещё"].firstMatch.tap()
        let занятие = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Занятие'")).firstMatch
        guard занятие.waitForExistence(timeout: 5) else { return }
        занятие.tap()
        _ = app.staticTexts["Он сделал"].waitForExistence(timeout: 5)
        capture("04-training")
    }

    func test05История() {
        app.tabBars.buttons["История"].tap()
        _ = app.navigationBars["История"].waitForExistence(timeout: 5)
        capture("05-history")
    }

    func test06Семья() {
        app.tabBars.buttons["Семья"].tap()
        _ = app.navigationBars["Семья"].waitForExistence(timeout: 5)
        capture("06-family")
    }

    func test07Подписка() {
        app.buttons["Настройки"].tap()
        let pro = app.descendants(matching: .any).matching(identifier: "Того Pro").firstMatch
        guard pro.waitForExistence(timeout: 5) else { return }
        pro.tap()
        _ = app.staticTexts["что открывает"].waitForExistence(timeout: 5)
        capture("07-paywall")
    }
}
