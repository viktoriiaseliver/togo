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


    func test12Прогулка() {
        app.buttons["Гулять"].firstMatch.tap()
        let пошли = app.buttons["Пошли"].firstMatch
        XCTAssertTrue(пошли.waitForExistence(timeout: 5))
        пошли.tap()

        let пописал = app.buttons["Пописал"].firstMatch
        XCTAssertTrue(пописал.waitForExistence(timeout: 5), "таймер должен пойти сразу")
        пописал.tap()
        пописал.tap()
        app.buttons["Стул"].firstMatch.tap()
        capture("12-walk-mode")
    }

    func test08Питание() {
        app.tabBars.buttons["Стич"].tap()
        найти("Питание и режим", в: app).tap()
        _ = app.navigationBars["Питание"].waitForExistence(timeout: 5)
        capture("08-feeding")
    }

    func test09Права() {
        app.tabBars.buttons["Семья"].tap()
        найти("Мама", в: app).tap()
        _ = app.staticTexts["ЧТО РАЗРЕШЕНО"].waitForExistence(timeout: 5)
        capture("09-permissions")
    }

    func test10Перенос() {
        app.buttons["Настройки"].tap()
        найти("Перенос и восстановление", в: app).tap()
        _ = app.navigationBars["Перенос"].waitForExistence(timeout: 5)
        capture("10-backup")
    }

    func test11Язык() {
        app.buttons["Настройки"].tap()
        найти("Язык", в: app).tap()
        _ = app.navigationBars["Язык"].waitForExistence(timeout: 5)
        capture("11-language")
    }

    func test07Подписка() throws {
        app.buttons["Настройки"].tap()
        let pro = app.descendants(matching: .any).matching(identifier: "Togo Pro").firstMatch
        guard pro.waitForExistence(timeout: 5) else { return }
        pro.tap()
        _ = app.staticTexts["что открывает"].waitForExistence(timeout: 5)
        // Цены приходят из StoreKit не мгновенно. Без этого ожидания
        // в кадр попадало пустое состояние «Цены не загрузились» —
        // и именно такой снимок чуть не уехал в App Review.
        let price = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '2,99' OR label CONTAINS '2.99'")
        ).firstMatch
        guard price.waitForExistence(timeout: 20) else {
            throw XCTSkip("""
                Цены не пришли, снимать нечего. Две причины разом: продукты \
                в App Store Connect стоят MISSING_METADATA и StoreKit их \
                не отдаёт даже в песочнице, а конфигурация Togo.storekit \
                в прогоне через xcodebuild не подхватывается. Пейволл \
                с надписью «Цены не загрузились» в витрину не годится.
                """)
        }
        capture("07-paywall")
    }
}
