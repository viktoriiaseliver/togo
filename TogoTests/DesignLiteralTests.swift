import Testing
import Foundation

/// Числа и цвета в слое вида.
///
/// Связывание с Figma держится на том, что оформление приходит из
/// токенов: один и тот же кегль в макете и в коде — это одно значение,
/// а не два похожих. Число, вписанное в вид руками, разрывает связь
/// молча — макет меняется, приложение нет, и никто не узнаёт.
///
/// Цвет и тень здесь **строго ноль**: на 23.09 их в слое вида нет
/// ни одного, и сторож не даёт появиться первому. Кегли, радиусы
/// и размеры — долг, он может только уменьшаться.
///
/// Опись и решения — `docs/FIGMA-ПОДГОТОВКА.md`.
@Suite("Оформление без литералов")
struct DesignLiteralTests {

    private static let слойВида = ["Togo/DesignSystem", "Togo/Features"]

    /// Долг по видам. Замер 23.09.2026.
    private let долг: [String: Int] = [
        "кегль": 36,
        "радиус": 3,
        "размер": 36,
    ]

    @Test("Цвета и теней в слое вида нет ни одного")
    func цветаНет() throws {
        let цвет = try Self.посчитать(
            #"\.(red|blue|green|yellow|orange|purple|pink|gray|grey|black|white)\b"#,
            плюс: [#"Color\(red:"#, "#[0-9A-Fa-f]{6}"])
        #expect(цвет.всего == 0, """
            литеральный цвет в слое вида: \(цвет.примеры.prefix(3).joined(separator: " | ")).
            Цвет приходит из Token.*, иначе макет и приложение расходятся молча.
            """)
        let тень = try Self.посчитать(#"\.shadow\("#)
        #expect(тень.всего == 0, """
            литеральная тень: \(тень.примеры.prefix(3).joined(separator: " | ")).
            Тень — токен уровня, а не четыре числа в месте применения.
            """)
    }

    @Test("Кеглей, радиусов и размеров числом не становится больше")
    func долгНеРастёт() throws {
        let виды: [String: String] = [
            "кегль": #"\.font\(\.system\(size: *[0-9]"#,
            "радиус": #"cornerRadius: *[0-9]|\.cornerRadius\( *[0-9]"#,
            "размер": #"\.frame\((width|height|minWidth|minHeight|maxHeight): *[0-9]"#,
        ]
        for (вид, шаблон) in viedSorted(виды) {
            let найдено = try Self.посчитать(шаблон)
            let разрешено = долг[вид] ?? 0
            #expect(найдено.всего <= разрешено, """
                \(вид): числом \(найдено.всего) при долге \(разрешено). \
                Нет подходящего токена — завести его в DesignTokens/tokens.json, \
                а не подставить число. Примеры: \
                \(найдено.примеры.prefix(3).joined(separator: " | "))
                """)
        }
    }

    private func viedSorted(_ виды: [String: String]) -> [(String, String)] {
        виды.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private static func посчитать(_ шаблон: String,
                                  плюс дополнительные: [String] = []) throws
        -> (всего: Int, примеры: [String]) {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var выражения = [try NSRegularExpression(pattern: шаблон)]
        выражения += try дополнительные.map { try NSRegularExpression(pattern: $0) }

        var всего = 0
        var примеры: [String] = []
        for каталог in слойВида {
            let база = корень.appendingPathComponent(каталог)
            let обход = FileManager.default.enumerator(at: база, includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "swift",
                      let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }
                for (номер, строка) in текст.components(separatedBy: .newlines).enumerated() {
                    let код = строка.components(separatedBy: "//")[0]
                    guard !код.contains("Token."), !код.isEmpty else { continue }
                    let диапазон = NSRange(код.startIndex..., in: код)
                    guard выражения.contains(where: {
                        $0.firstMatch(in: код, range: диапазон) != nil
                    }) else { continue }
                    всего += 1
                    if примеры.count < 5 {
                        примеры.append("\(элемент.lastPathComponent):\(номер + 1)")
                    }
                }
            }
        }
        return (всего, примеры)
    }
}
