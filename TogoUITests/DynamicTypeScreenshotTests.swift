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

    // Четыре экрана выше дали шесть дефектов за один час 28.09 —
    // все шесть про раскладку, которой не хватает ширины. Экранов
    // в приложении больше четырёх, и пока их не сняли, «не нашли»
    // означает «не смотрели».
    //
    // Ниже — остальные вкладки и один лист записи. Лист важен отдельно:
    // на главном экране всё крупное, а в шторках плотнее всего.

    func testXL06История() {
        app.tabBars.buttons["История"].tap()
        _ = app.navigationBars["История"].waitForExistence(timeout: 5)
        capture("xl-06-history")
        app.swipeUp()
        capture("xl-06-history-scrolled")
    }

    func testXL07Здоровье() throws {
        // Вкладка условная: `RootView:46` показывает её только когда
        // `dog?.isOnTreatment == true` И есть право `seeMedical`.
        // В наборе UI-тестов собака не на лечении, поэтому вкладки нет.
        //
        // Пропуск ЯВНЫЙ, а не тихое «не нашли». Тест, который молча
        // проходит, не найдя предмета, молчит так же, как тест,
        // у которого всё хорошо, — и эту поверхность на крупном шрифте
        // не увидит никто.
        let вкладка = app.tabBars.buttons["Здоровье"]
        try XCTSkipUnless(вкладка.waitForExistence(timeout: 3),
                          "Вкладки «Здоровье» нет: собака в наборе не на лечении. "
                          + "Экран на крупном шрифте НЕ ПРОВЕРЕН — нужен сценарий с лечением.")
        вкладка.tap()
        _ = app.navigationBars["Здоровье"].waitForExistence(timeout: 5)
        capture("xl-07-health")
        app.swipeUp()
        capture("xl-07-health-scrolled")
    }

    func testXL08Собака() {
        app.tabBars.buttons["Стич"].tap()
        _ = app.staticTexts["Стич"].firstMatch.waitForExistence(timeout: 5)
        capture("xl-08-dog")
        app.swipeUp()
        capture("xl-08-dog-scrolled")
    }

    func testXL09ЛистЕды() {
        app.buttons["Еда"].firstMatch.tap()
        // Шторка поднимается не мгновенно; ждём её содержимое,
        // а не таймаут — иначе кадр снимется на анимации.
        _ = app.buttons["Записать"].firstMatch.waitForExistence(timeout: 5)
        capture("xl-09-meal-sheet")
    }

    /// Приёмка листалки дня: запись, сделанная на прошлом дне, обязана
    /// лечь В ТОТ день и сказать об этом человеку.
    ///
    /// Снимается при обычном кегле — это не про размер текста, а про
    /// то, куда попадает запись. Лежит здесь, потому что здесь уже
    /// собрана оснастка кадров; переедет, когда их станет больше.
    func testВчераЗапись() {
        app.buttons["Предыдущий день"].firstMatch.tap()
        _ = app.staticTexts["В сегодня"].waitForExistence(timeout: 3)
        capture("вчера-01-экран")
        app.buttons["Еда"].firstMatch.tap()
        _ = app.buttons["Записать"].firstMatch.waitForExistence(timeout: 5)
        app.buttons["Записать"].firstMatch.tap()
        capture("вчера-02-подтверждение")
    }

    func testXL10Стул() {
        app.buttons["Стул"].firstMatch.tap()
        _ = app.staticTexts["форма"].firstMatch.waitForExistence(timeout: 5)
        capture("xl-10-stool")
        app.swipeUp()
        capture("xl-10-stool-scrolled")
    }

    func testXL11Инцидент() {
        app.buttons["Инцидент"].firstMatch.tap()
        _ = app.staticTexts["что случилось"].firstMatch.waitForExistence(timeout: 5)
        capture("xl-11-incident")
    }

    func testXL12Питание() {
        app.tabBars.buttons["Стич"].tap()
        let питание = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Питание")).firstMatch
        _ = питание.waitForExistence(timeout: 5)
        питание.tap()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
        capture("xl-12-feeding")
        app.swipeUp()
        capture("xl-12-feeding-scrolled")
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
