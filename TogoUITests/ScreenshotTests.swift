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

    /// Кадр пейволла для App Review — и сторож на то, что цены вообще есть.
    ///
    /// Пропуска здесь больше нет, и это главное. Раньше тест, не дождавшись
    /// цен, бросал `XCTSkip` — и прогон отвечал `** TEST SUCCEEDED **`
    /// с кодом возврата 0. Сторож стоял ровно на том, что держит релиз,
    /// и молчал: кадр с надписью «Цены не загрузились» уехал в App Store
    /// Connect именно так.
    ///
    /// Под `xcodebuild` тест сегодня красный, и красный по делу — цен
    /// в пейволле нет. Замеры 23.09, чтобы следующий не искал заново:
    ///
    /// - ссылка на `Configuration/Togo.storekit` в схеме есть (`TestAction`
    ///   и `LaunchAction`), путь резолвится — до приложения не доезжает;
    /// - `SKTestSession` из теста тоже не помогает: файл она читает
    ///   (2355 байт; несуществующий путь честно отвергает,
    ///   `SKTestErrorDomain Code=4`), но `Product.products` отдаёт пусто —
    ///   и в процессе раннера, и внутри процесса приложения (проверено
    ///   модульным тестом, он идёт в `Togo.app` через `TEST_HOST`);
    /// - план тестов со `storeKitConfigurationFileReference` на чистом
    ///   симуляторе — тот же пустой результат.
    ///
    /// Пусто — это ответ, а не «не успело»: пейволл показывает «Цены
    /// не загрузились» только когда загрузка кончилась (`TGStateful`
    /// с `isLoading: false`), и баннера ошибки при этом нет.
    ///
    /// Из Xcode цены приходят — там кадр и снимается, пока способа снять
    /// его из командной строки не нашлось. Неисключённое объяснение одно:
    /// формат `.storekit` version 4.0 против Xcode 27.
    func test07Подписка() {
        app.buttons["Настройки"].tap()
        let pro = app.descendants(matching: .any).matching(identifier: "Togo Pro").firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 5), "в настройках нет входа в «Togo Pro»")
        pro.tap()
        XCTAssertTrue(app.staticTexts["что открывает"].waitForExistence(timeout: 5),
                      "пейволл не открылся")

        // Цены приходят из StoreKit не мгновенно. Без этого ожидания
        // в кадр попадало пустое состояние «Цены не загрузились» —
        // и именно такой снимок чуть не уехал в App Review.
        let month = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '2,99' OR label CONTAINS '2.99'")
        ).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 20), """
            Пейволл не показал месячную цену 2,99 из Configuration/Togo.storekit. \
            В кадре либо «Цены не загрузились», либо «Спрашиваю цены у App Store…» — \
            в App Review такой кадр не годится.
            """)
        let year = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '19,99' OR label CONTAINS '19.99'")
        ).firstMatch
        XCTAssertTrue(year.exists, "пейволл показал месяц, но не год — планов в кадре должно быть два")

        capture("07-paywall")
    }
}
