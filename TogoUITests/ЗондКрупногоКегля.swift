import XCTest

/// Зонд: **меняется ли кегль от аргумента запуска** — и ничего больше.
///
/// Повод. Сессия картинок замерила 25.10.2026, что `ImageRenderer`
/// кегль **не меняет вовсе**: `AppFont` считает размер через
/// `UIFontMetrics(forTextStyle:).scaledValue(for:)`
/// (`Typography.swift:44`), а тот читает настройку **процесса**,
/// а не `\.dynamicTypeSize` окружения SwiftUI и не
/// `UITraitCollection.current`. Пары кадров совпали побайтово.
/// Значит все наборы, снятые через `ImageRenderer`, сняты
/// на обычном кегле, как бы они ни назывались.
///
/// Отсюда гипотеза: сменить кегль можно только у **процесса**, то есть
/// аргументом запуска `-UIPreferredContentSizeCategoryName`. Гипотезу
/// надо померить, а не принять: ровно тем же способом уже пользуются
/// `DynamicTypeScreenshotTests` (AX3) и `КрупныйКегльБезДвухРаскладок`
/// (AX1), и **ни одного замера, что он работает, в проекте нет**.
///
/// ## Чем меряет
///
/// Два числа с одного и того же экрана, в одном и том же заходе:
///
/// ```
/// ПРЕДМЕТ   высота подписи «Стич» в шапке «Сегодня».
///           Стиль posterHeaderTitle, relativeTo .largeTitle —
///           растёт от кегля по построению
/// КОНТРОЛЬ  app.frame — размер окна. От кегля не зависит НИКАК.
///           Если поедет и он, померено не то
/// ```
///
/// И третий заход — `C-контроль` — повторяет первый **с теми же
/// аргументами**. Он нужен для md5: кадр содержит часы и живые данные,
/// и без него «хеши разошлись» не отличить от «кегль сменился».
/// Контроль снят в том же прогоне, что предмет, — из прежнего вывода
/// его брать нельзя.
///
/// Кадры ложатся в `build/зонд-кегля/`, хеши считаются снаружи.
nonisolated final class ЗондКрупногоКегля: XCTestCase {

    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/зонд-кегля")
    }

    private func прогон(_ имя: String, кегль: String?) {
        continueAfterFailure = false
        let app = XCUIApplication()
        var аргументы = ["-UITesting"]
        if let кегль {
            аргументы += ["-UIPreferredContentSizeCategoryName", кегль]
        }
        app.launchArguments = аргументы
        app.launch()

        let метка = app.staticTexts["Стич"].firstMatch
        XCTAssertTrue(метка.waitForExistence(timeout: 60),
                      "\(имя): приложение не дошло до «Сегодня» — мерить нечего")
        // Кадр снимается после того, как шапка встала: иначе предмет
        // меряется на анимации появления.
        Thread.sleep(forTimeInterval: 1.5)

        let рамка = метка.frame
        let окно = app.frame
        print("ЗОНД|\(имя)|кегль=\(кегль ?? "ПО-УМОЛЧАНИЮ")" +
              "|предмет-высота=\(рамка.height)|предмет-ширина=\(рамка.width)" +
              "|контроль-окно=\(окно.width)x\(окно.height)")

        let снимок = app.screenshot()
        let вложение = XCTAttachment(screenshot: снимок)
        вложение.name = имя
        вложение.lifetime = .keepAlways
        add(вложение)
        do {
            try FileManager.default.createDirectory(at: каталог,
                                                    withIntermediateDirectories: true)
            try снимок.pngRepresentation.write(to: каталог.appendingPathComponent("\(имя).png"))
            print("ЗОНД-КАДР-ЛЁГ|\(имя)")
        } catch {
            print("ЗОНД-КАДР-НЕ-ЛЁГ|\(имя)|\(error.localizedDescription)")
        }
        app.terminate()
    }

    func testЗондAОбычный() { прогон("A-обычный", кегль: nil) }

    func testЗондBAX5() {
        прогон("B-ax5", кегль: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    func testЗондCКонтроль() { прогон("C-контроль", кегль: nil) }
}
