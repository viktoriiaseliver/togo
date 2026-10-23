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

    /// **Дорога переписана 23.10.2026: шестерёнки на «Сегодня» больше
    /// нет.** Редизайн убрал её в меню «…» (решение Виктории 22.10,
    /// хендофф iOS 28: «одна кнопка „…" в шапке, больше кнопок нет»).
    ///
    /// Прежняя редакция искала `app.buttons["Настройки"]` сразу после
    /// запуска. Замер дерева 23.10: на «Сегодня» **14 кнопок, и такой
    /// среди них нет**. Нашла это не приёмка кадров, а соседняя сессия
    /// попутно — тест либо падал, либо снимал кадр не того экрана.
    ///
    /// > **Тест, ищущий кнопку по имени, ломается от переноса кнопки
    /// > молча.** Кадр при этом получается: непустой, с интерфейсом,
    /// > и выглядит как приёмка. Различает только имя экрана в панели
    /// > навигации — оно проверяется ниже и до правки не проверялось.
    ///
    /// Дорога взята у живых тестов редизайна — `НастройкиКино.swift:84`
    /// и `ШапкаПлаката.swift:394` ходят через `шапка-меню`.
    func testXL03Настройки() {
        let меню = app.buttons["шапка-меню"].firstMatch
        XCTAssertTrue(меню.waitForExistence(timeout: 5), """
            на «Сегодня» нет кнопки «…» (`шапка-меню`) — дорога в настройки \
            снова изменилась. Кнопка «Настройки» на главном экране убрана \
            редизайном 22.10.2026, и если нет уже и меню, искать надо \
            не здесь, а в том, что пришло ему на смену.
            """)
        меню.tap()
        app.buttons["Настройки"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5),
                      "после «…» → «Настройки» экран настроек не открылся")
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

    /// Вкладка условная: `RootView:46` показывает её только когда
    /// `dog?.isOnTreatment == true` И есть право `seeMedical`.
    ///
    /// **Тест пропускался с 05.10, и автор был прав, что пропускал.**
    /// Пропуск явный, с названной причиной — «нужен сценарий
    /// с лечением»; тихо пройти, не найдя предмета, было бы хуже.
    ///
    /// Но по нашему же определению зелёного прогона **ноль `skipped`
    /// входит в условие**, а в итоговой строке пропуск виден как
    /// служебное «1 test skipped» — и читался он служебной строкой,
    /// а не нарушением условия. Экран здоровья на крупном шрифте
    /// не видел никто ни разу; набор при этом молчал зелёным.
    ///
    /// > **Пропуск с честной причиной опаснее пропуска без неё:**
    /// > причина объясняет, почему тест молчит, и тем закрывает
    /// > вопрос вместо того, чтобы его задать.
    ///
    /// **Чинится входом, а не данными по умолчанию.** Поставь
    /// `isOnTreatment` в общий набор — сдвинутся кадры остальных
    /// шести `testXL*`. Поэтому приложение перезапускается здесь
    /// и только здесь, на `amber`: он уже включает лечение
    /// (`SeedData:376`), заведён 05.10 ради янтаря, и ничьих данных
    /// эта правка не трогает.
    ///
    /// **Приёмка — кадр, а не зелень.** «Тест перестал пропускаться»
    /// и «экран проверен» — разные утверждения; второе доказывает
    /// только взгляд на `xl-07-health`.
    func testXL07Здоровье() throws {
        app.terminate()
        app.launchArguments = [
            "-UITesting",
            "-Сценарий", "amber",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXL",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Стич"].firstMatch.waitForExistence(timeout: 15),
                      "сценарий с лечением не построился — проверять нечего")

        let вкладка = app.tabBars.buttons["Здоровье"]
        XCTAssertTrue(вкладка.waitForExistence(timeout: 10), """
            вкладки «Здоровье» нет даже на сценарии с лечением. Либо \
            `amber` перестал ставить `isOnTreatment`, либо вкладку \
            закрывает право `seeMedical` — и тогда это находка, \
            а не повод снова пропускать.
            """)
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

    /// Приёмка записи попыток: счёт обязан вырасти, а не остаться нулём.
    ///
    /// До 28.09 `attempts` не увеличивал никто, и строка «N из M»
    /// не появлялась ни разу. Тест снимает ДО и ПОСЛЕ — иначе «ноль»
    /// и «не показали» неотличимы.
    func testНавыкПопытка() {
        app.tabBars.buttons["Стич"].tap()
        let процедуры = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "роцедур")).firstMatch
        guard процедуры.waitForExistence(timeout: 5) else {
            XCTFail("не нашла вход в «Процедуры» — проверь вкладку собаки")
            return
        }
        процедуры.tap()
        capture("навык-01-до")
        let первый = app.staticTexts["Дать лапу и не забирать"]
        _ = первый.waitForExistence(timeout: 5)
        первый.tap()
        _ = app.buttons["Получилось"].waitForExistence(timeout: 5)
        app.buttons["Получилось"].tap()
        app.buttons["Получилось"].tap()
        capture("навык-02-лист")
        app.buttons["Закрыть"].firstMatch.tap()
        capture("навык-03-после")
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
