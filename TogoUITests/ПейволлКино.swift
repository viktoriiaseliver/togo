import XCTest

/// Кадр экрана «Togo Pro» рядом с эталоном
/// `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/17.png`.
///
/// # Зачем отдельный файл рядом с `ScreenshotTests.test07Подписка`
///
/// Сосед делает ДРУГОЕ и делать это должен: он вкладывает кадр
/// в `.xcresult` как `XCTAttachment` — для витрины App Store, — и там
/// же стережёт, что цены вообще приходят. Кадр приёмки дизайна нужен
/// **файлом на диске**, потому что его кладут рядом с эталоном
/// в `Дизайн/кадры-приёмки/` и коммитят; вложение в `.xcresult` туда
/// не попадает, а `build/` в `.gitignore`.
///
/// # Чего этот кадр НЕ покажет, и это замер, а не оговорка
///
/// **Списка цен на нём не будет.** Из командной строки `Product.products`
/// отдаёт пусто: локальная конфигурация `Configuration/Togo.storekit`
/// под `xcodebuild` до симулятора не доезжает, а живой магазин ничего
/// не отдаёт, пока не подписано Соглашение о платных приложениях.
/// Замеры 23.09.2026 перечислены в голове `ScreenshotTests.test07Подписка`
/// поимённо — повторять их здесь нечем и незачем.
///
/// Значит на кадре будет пустое состояние вместо двух планов. Всё
/// остальное — шапка «Togo Pro · ровно три вещи», три строки Pro,
/// строка «бесплатно навсегда», правовой текст и обе кнопки низа —
/// настоящее и сверяется с эталоном.
///
/// > **Пустое состояние тут не дефект кадра, а ЕГО ЖЕ предмет.** Оно
/// > обязано называть причину: «обычно это связь» стояло в этом месте
/// > всегда и было догадкой, а магазин отвечал пустым списком без
/// > единой ошибки связи.
nonisolated final class ПейволлКино: XCTestCase {

    private var app: XCUIApplication!

    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-пейволла")
    }

    /// Имя переменной латиницей: кириллическое оболочка не заводит
    /// вовсе, и подстановка молча отдаёт пустоту.
    private var суффикс: String {
        let значение = ProcessInfo.processInfo.environment["KADR_SUFFIX"] ?? ""
        return значение.isEmpty ? "" : "-\(значение)"
    }

    private var снято: [String] = []

    override func setUp() {
        continueAfterFailure = false
        снято = []
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
    }

    override func tearDown() {
        // Счёт печатается ВСЕГДА, в том числе после падения: «снято два»
        // и «упал на первом, снято ноль» выглядят в логе одинаково —
        // во втором случае строк `КАДР:` просто нет, а их отсутствия
        // никто не ищет.
        print("КАДРОВ СНЯТО: \(снято.count) из 1 · \(снято.joined(separator: ", "))")
    }

    @discardableResult
    private func снять(_ имя: String) -> Bool {
        let кадр = app.screenshot()
        do {
            try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
            let путь = каталог.appendingPathComponent("\(имя)\(суффикс).png")
            try кадр.pngRepresentation.write(to: путь)
            снято.append(имя)
            print("КАДР: \(путь.path) · \(кадр.pngRepresentation.count) байт")
            return true
        } catch {
            print("КАДР НЕ ЗАПИСАН: \(имя) · \(error)")
            return false
        }
    }

    func testКадрПейволла() {
        XCTAssertTrue(app.staticTexts["Стич"].waitForExistence(timeout: 20),
                      "приложение не поднялось — дальше снимать нечего")

        XCTAssertTrue(открытьНастройки(в: app), """
            В настройки не попали. С 22.10.2026 шестерёнки в шапке
            «Сегодня» нет — настройки первым пунктом меню «…»,
            и помощник `открытьНастройки` пробует оба пути.
            """)

        // Кнопку, а не любой элемент с этим именем: первым совпадением
        // бывает StaticText внутри строки, тап по нему в лист не уводит,
        // и падение приходит под именем «пейволл не открылся».
        let pro = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Togo Pro'")
        ).firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 10),
                      "в настройках нет кнопки «Togo Pro»")
        pro.tap()

        // Якорь — подзаголовок листа. Заголовка секции «что открывает»
        // на этом экране больше нет: редизайн 23.10.2026 свёл шапку
        // к «Togo Pro · ровно три вещи».
        XCTAssertTrue(app.staticTexts["ровно три вещи"].waitForExistence(timeout: 15),
                      "пейволл не открылся")

        снять("17-togo-pro")

        // Обе кнопки низа обязаны быть на кадре: главная называет цену
        // (или «Выбери план», когда магазин молчит), вторая отказывает
        // без выхода с экрана. Проверка не про вид, а про то, что
        // кадр снят с целого экрана, а не с половины.
        XCTAssertTrue(app.buttons["Не сейчас"].firstMatch.exists, """
            На экране нет «Не сейчас». Либо низ не нарисовался, либо
            кадр снят не с пейволла — смотреть сам кадр, он уже записан.
            """)

        XCTAssertEqual(снято.count, 1,
                       "кадр не записался: смотреть строки «КАДР НЕ ЗАПИСАН» в логе")
    }
}
