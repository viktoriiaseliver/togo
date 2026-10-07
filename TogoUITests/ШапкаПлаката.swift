import XCTest

/// Кадр ЖИВОГО экрана с шапкой-плакатом — и кадр ложится файлом.
///
/// **Зачем отдельно от модульного замера.** `EmptyStateFrameTests`
/// растеризует `TGPosterHeader` сам по себе и доказывает цвет
/// и контраст. Он не видит самого дорогого вопроса: как шапка
/// складывается с системной панелью. `ImageRenderer` навигационную
/// панель не рисует вовсе, то есть «титул в баре погашен» для него
/// невыразимо.
///
/// Это и есть разница между «компонент верен» и «экран выглядит так».
/// У нас записано ценой кнопки с контрастом 1,68:1: значение верное,
/// а вызов бессильный, и ловит это только кадр того, что человек
/// правда видит.
///
/// **Почему файлом, а не `XCTAttachment`.** Замер: `xcresulttool export
/// attachments` не выгрузился **пять раз из девяти**, пакет `.xcresult`
/// остаётся без `Info.plist`. Вложение, которое не выгружается, —
/// это кадр, которого нет. PNG по `#filePath` переживает и обрыв
/// прогона, а путь печатается в сообщении: сообщение попадает в лог
/// всегда.
/// `nonisolated` — как у соседних наборов, и это не оформление:
/// `XCTestCase.setUp()` объявлен вне актора, а класс без пометки
/// в Swift 6 получает `@MainActor` по умолчанию и перестаёт
/// переопределять то, что собирался. Компилятор говорит об этом
/// прямо («different actor isolation from nonisolated overridden
/// declaration»), но указывает на `setUp` и на `init(invocation:)`,
/// а причина — в объявлении класса строкой выше.
nonisolated final class ШапкаПлаката: XCTestCase {

    private var app: XCUIApplication!

    /// Куда ложатся кадры. Рядом с модульными, в дереве.
    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-пустых-состояний")
    }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
    }

    /// Снять окно ПРИЛОЖЕНИЯ и положить файлом.
    ///
    /// `app.screenshot()`, а не `XCUIScreen.main.screenshot()`: экран
    /// принадлежит симулятору, окно — приложению. На общей машине это
    /// разные вещи, и 23.09 общий симулятор дал чужое приложение
    /// на всех пяти кадрах при зелёном прогоне.
    @discardableResult
    private func снять(_ имя: String) throws -> URL {
        let кадр = app.screenshot()
        try FileManager.default.createDirectory(at: каталог,
                                                withIntermediateDirectories: true)
        let путь = каталог.appendingPathComponent("\(имя).png")
        try кадр.pngRepresentation.write(to: путь)
        print("КАДР: \(путь.path) · \(кадр.pngRepresentation.count) байт")
        return путь
    }

    func testШапкаПлакатаНаЖивыхНастройках() throws {
        let шестерёнка = app.buttons["Настройки"].firstMatch
        XCTAssertTrue(шестерёнка.waitForExistence(timeout: 10),
                      "до настроек не дошли — кадра нет, и это не «шапки нет»")
        шестерёнка.tap()

        // Панель существует — значит экран тот. Проверяется ДО съёмки:
        // пустой кадр не сообщает, чей он.
        let панель = app.navigationBars.firstMatch
        XCTAssertTrue(панель.waitForExistence(timeout: 10),
                      "навигационной панели нет — экран не тот или не успел")

        let путь = try снять("живые-настройки-шапка")

        // Заголовок экрана должен существовать РОВНО ОДИН раз.
        //
        // Это и есть вопрос, ради которого снимается живой кадр:
        // `.navigationBarTitleDisplayMode(.inline)` рисует название
        // в панели, а шапка-плакат рисует его же крупно. Два
        // заголовка подряд — не «плакат плюс навигация», а два
        // заголовка.
        //
        // Названная граница: это счёт ЭЛЕМЕНТОВ, а не пикселей.
        // Он поймает «титул остался в баре» и не поймает «в баре
        // осталась дыра на его месте» — последнее видно только
        // на кадре, и кадр лежит рядом.
        let заголовки = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Настройки"))
        XCTAssertEqual(заголовки.count, 1, """
            название экрана встречается \(заголовки.count) раз(а).
            Ждём один: титул в панели погашен пустым `principal`,
            крупный живёт в шапке-плакате.
            Кадр: \(путь.path)
            """)
    }
}
