import XCTest

/// Приёмка снятия `ViewThatFits` — кадром на **AX1** и разбором
/// ДЕРЕВА ЭЛЕМЕНТОВ, а не только видом.
///
/// Красная линия проекта запрещает `ViewThatFits` по измеренной
/// причине: он держит в дереве **обе** раскладки одновременно,
/// и озвучка находила **две кнопки «Отменить»** — человек
/// с VoiceOver не мог понять, какую нажимает.
///
/// > **Поэтому взгляда на кадр недостаточно, и это суть теста.**
/// > При `ViewThatFits` кадр ПРАВИЛЬНЫЙ: рисуется ровно одна ветка.
/// > Вторая живёт в дереве доступности, где её не видно глазами
/// > и не видно компилятору. Кадр отвечает «верно ли сказано»,
/// > счёт элементов — «сколько их там лежит», и это разные вопросы.
///
/// ## Почему именно AX1, а не `AccessibilityXL`
///
/// `DynamicTypeScreenshotTests` снимает на `AccessibilityXL` (AX3).
/// Здесь нарочно **AX1** (`UICTContentSizeCategoryAccessibilityM`):
/// это **первая** ступень, на которой `.isAccessibilitySize`
/// становится истинным, то есть граница переключения раскладки.
/// Ступень выше проходит заведомо; ломается — ровно первая.
///
/// ## Что снимается
///
/// Два экрана, по одному на каждый тронутый компонент:
///
/// ```
/// Настройки                      TGListRow  — его зовёт КАЖДАЯ строка настроек
/// «Если что-то случилось»        LabeledField — 7 вызовов на одном экране
/// ```
///
/// **Экрана онбординга здесь нет, и это замер, а не пропуск.**
/// `LabeledField` объявлен в `Togo/Features/Onboarding/OnboardingSteps.swift`,
/// но онбординг его **не зовёт ни разу** (замер 23.10.2026: 49 вызовов
/// в 11 файлах, все в `Health`, `Profile`, `Emergency`, `Trip`,
/// `Feeding`, `Family`). Кадр онбординга показал бы не тот предмет
/// под именем этого.
///
/// **Куда пишет.** `build/кадры-крупный-кегль/`, путь выведен
/// из `#filePath`. `build/` в `.gitignore`: то, что нужно сохранить,
/// выносится в `Дизайн/кадры-приёмки/` и коммитится отдельно.
nonisolated final class КрупныйКегльБезДвухРаскладок: XCTestCase {

    private var app: XCUIApplication!
    private var снято: [String] = []

    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-крупный-кегль")
    }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UIPreferredContentSizeCategoryName",
            // AX1 — первая ступень, где .isAccessibilitySize == true.
            "UICTContentSizeCategoryAccessibilityM",
        ]
        app.launch()
    }

    /// Счёт печатается ВСЕГДА и в том числе после падения посреди
    /// прохода: «снято четыре» и «упал на втором, снято одно» выглядят
    /// в логе одинаково — строк `КАДР:` просто меньше, а отсутствия
    /// никто не ищет.
    override func tearDown() {
        print("КАДРОВ СНЯТО: \(снято.count) · \(name) · \(снято.joined(separator: ", "))")
    }

    /// Кадр окна файлом, а не `XCTAttachment`: выгрузка вложений
    /// в этом проекте измерена и не сработала пять раз из девяти.
    /// Вложение, которое не выгружается, — это кадр, которого нет.
    @discardableResult
    private func снять(_ имя: String) throws -> URL {
        let кадр = app.screenshot()
        try FileManager.default.createDirectory(at: каталог,
                                                withIntermediateDirectories: true)
        let путь = каталог.appendingPathComponent("\(имя).png")
        try кадр.pngRepresentation.write(to: путь)
        снято.append(имя)
        print("КАДР: \(путь.path) · \(кадр.pngRepresentation.count) байт")
        return путь
    }

    // MARK: - Счёт в дереве

    /// Сколько РАЗНЫХ элементов дерева несут ровно эту подпись.
    ///
    /// Тип спрашивается точно (`staticTexts`), а не `descendants(.any)`:
    /// у строки списка контейнер собирает подпись детей, и тогда два
    /// вхождения законны даже у здоровой раскладки. Нас интересует
    /// число самих `Text`, потому что именно их `ViewThatFits`
    /// удваивает.
    private func подписей(_ подпись: String) -> Int {
        app.staticTexts.matching(
            NSPredicate(format: "label == %@", подпись)).count
    }

    /// Вердикт точный: имя подписи и её число, а не «дерево сломано».
    private func ровноОдна(_ подпись: String, экран: String) {
        let сколько = подписей(подпись)
        XCTAssertEqual(сколько, 1, """
            на экране «\(экран)» подпись «\(подпись)» лежит в дереве \
            \(сколько) раз(а) вместо одного. При двух это вернувшийся \
            ViewThatFits: он держит ОБЕ раскладки, и озвучка читает \
            один орган дважды — так появились две кнопки «Отменить». \
            Кадр при этом правильный, глазами такое не ловится.
            """)
    }

    // MARK: - Экран 1 · настройки (TGListRow)

    func testAX1НастройкиОднаРаскладкаВДереве() throws {
        app.buttons["Настройки"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 10),
                      "экран «Настройки» не открылся — снимать и считать нечего")

        // Было что проверять: предмет на экране ЕСТЬ. Без этого
        // «ровно одна» выполняется и при нуле — утверждение,
        // которого дефект не нарушает, сторожем не бывает.
        let предмет = app.staticTexts["Фон приложения"].firstMatch
        XCTAssertTrue(предмет.waitForExistence(timeout: 10), """
            строки «Фон приложения» на экране нет вовсе. Либо она \
            переименована, либо экран не тот — и тогда счёт ниже \
            ничего не значит: ноль и один он не различает.
            """)

        try снять("ax1-01-настройки")
        ровноОдна("Фон приложения", экран: "Настройки")

        app.swipeUp()
        try снять("ax1-02-настройки-ниже")
    }

    // MARK: - Экран 2 · «Если что-то случилось» (LabeledField)

    func testAX1ЭкстренныйЭкранОднаРаскладкаВДереве() throws {
        let бар = app.tabBars.firstMatch
        XCTAssertTrue(бар.waitForExistence(timeout: 15),
                      "таб-бара нет — приложение не дошло до главного экрана")
        // Вкладка собаки названа кличкой, то есть её имя — данные.
        // Берём по порядку: «Сегодня» · {кличка} · «История» · «Здоровье».
        бар.buttons.element(boundBy: 1).tap()

        let вход = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Если что-то случилось")).firstMatch
        XCTAssertTrue(вход.waitForExistence(timeout: 10),
                      "баннера «Если что-то случилось» нет — до LabeledField не дойти")
        вход.tap()

        let предмет = app.staticTexts["Чип"].firstMatch
        XCTAssertTrue(предмет.waitForExistence(timeout: 10), """
            подписи «Чип» нет — экран «Если что-то случилось» \
            не открылся или поле переименовано. Счёт ниже тогда \
            не про предмет.
            """)

        try снять("ax1-03-экстренный")

        // Три подписи, каждая на экране одна по смыслу.
        for подпись in ["Чип", "Паспорт", "Страховка"] {
            ровноОдна(подпись, экран: "Если что-то случилось")
        }

        app.swipeUp()
        try снять("ax1-04-экстренный-ниже")
    }
}
