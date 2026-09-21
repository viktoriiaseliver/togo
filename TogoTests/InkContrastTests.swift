import Testing
import Foundation
import SwiftUI
@testable import Togo

@Suite("Контраст текста и значков")
struct InkContrastTests {

    /// Поверхности, на которых вообще что-то рисуется.
    nonisolated private static let surfaces: [(String, Color)] = [
        ("экран", Token.Surface.screen),
        ("карточка", Token.Surface.card),
        ("утопленное", Token.Surface.sunken),
    ]

    nonisolated private static let inks: [(String, Color)] = [
        ("primary", Token.Ink.primary),
        ("secondary", Token.Ink.secondary),
        ("silhouette", Token.Ink.silhouette),
    ]

    /// Все чернила, которыми РАЗРЕШЕНО красить текст, обязаны брать 4,5:1.
    ///
    /// `faint` в списке нет намеренно: он даёт 2,5:1 и текстом не красится.
    /// Проверку на него держит тест ниже — тот, что смотрит в исходники.
    @Test("Чернила текста берут порог 4,5:1", arguments: inks, surfaces)
    func inkMeetsThreshold(ink: (String, Color), surface: (String, Color)) {
        let ratio = Contrast.ratio(ink.1, on: surface.1)
        #expect(
            ratio >= 4.5,
            "«\(ink.0)» на «\(surface.0)»: \(ratio.formatted(.number.precision(.fractionLength(2)))):1"
        )
    }

    /// **`Ink.faint` не красит ни текст, ни значки — нигде.**
    ///
    /// Дыра, ради которой сторож заведён. У токена стояла подпись
    /// «слабый серый допустим только с 14pt» — и по этому разрешению он
    /// разошёлся по двадцати четырём файлам, включая порции корма 10 pt
    /// и строку «осталось 3 из 7». Замер: **2,5:1** на экране и на
    /// карточке. Разрешения «с 14pt» не существует: WCAG даёт послабление
    /// только тексту от 18 pt, и то до 3:1.
    ///
    /// Проверка лексическая, и это сознательно: цвет применяется в вёрстке,
    /// а не в токене, поэтому поймать его можно только там, где он написан.
    @Test("Faint не применяется как цвет переднего плана")
    func faintIsNeverAForegroundColour() throws {
        let запрещённые = [
            "foregroundStyle(Token.Ink.faint)",
            "color(Token.Ink.faint)",
            "stroke(Token.Ink.faint",
            "fill(Token.Ink.faint",
            "return Token.Ink.faint",
        ]

        var найдено: [String] = []
        for корень in ["Togo", "TogoWidgets"] {
            let папка = Self.repoRoot.appending(path: корень)
            guard let обход = FileManager.default.enumerator(at: папка,
                                                            includingPropertiesForKeys: nil)
            else { continue }
            for случай in обход {
                guard let файл = случай as? URL, файл.pathExtension == "swift" else { continue }
                // Галерея компонентов показывает палитру целиком, включая
                // то, чем красить нельзя: это её работа.
                guard файл.lastPathComponent != "ComponentGallery.swift" else { continue }
                guard let текст = try? String(contentsOf: файл, encoding: .utf8) else { continue }

                for (номер, строка) in текст.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where запрещённые.contains(where: строка.contains) {
                    найдено.append("\(файл.lastPathComponent):\(номер + 1) — \(строка.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(
            найдено.isEmpty,
            """
            Ink.faint даёт 2,5:1 и передним планом не красится:
            \(найдено.joined(separator: "\n"))
            """
        )
    }

    /// Проверка подделкой: сам порог должен быть достижимо строгим.
    /// Если `faint` однажды возьмёт 4,5:1, запрет выше станет лишним —
    /// и об этом надо узнать от теста, а не гадать.
    @Test("Faint и правда не проходит порог — иначе запрет бессмыслен")
    func faintReallyFailsTheThreshold() {
        for (имя, поверхность) in Self.surfaces {
            let ratio = Contrast.ratio(Token.Ink.faint, on: поверхность)
            #expect(
                ratio < 4.5,
                "faint на «\(имя)» взял \(ratio.formatted(.number.precision(.fractionLength(2)))):1 — запрет пора пересмотреть"
            )
        }
    }

    /// Корень репозитория от файла теста: путь до исходников не зависит
    /// от того, где лежит собранный бандл.
    nonisolated private static let repoRoot: URL = {
        URL(filePath: #filePath)            // …/TogoTests/InkContrastTests.swift
            .deletingLastPathComponent()    // …/TogoTests
            .deletingLastPathComponent()    // …/Того
    }()
}

/// Контраст по WCAG с учётом прозрачности чернил.
///
/// Считать без смешивания нельзя: `faint` и `secondary` — один и тот же
/// цвет с разной прозрачностью, и вся разница между 2,5:1 и 6,2:1 живёт
/// именно в ней.
enum Contrast {
    static func ratio(_ ink: Color, on surface: Color) -> Double {
        let фон = components(surface)
        let чернила = components(ink)
        let смешано = (
            чернила.0 * чернила.3 + фон.0 * (1 - чернила.3),
            чернила.1 * чернила.3 + фон.1 * (1 - чернила.3),
            чернила.2 * чернила.3 + фон.2 * (1 - чернила.3)
        )
        let a = luminance(смешано), b = luminance((фон.0, фон.1, фон.2))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func components(_ colour: Color) -> (Double, Double, Double, Double) {
        let ui = UIColor(colour)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }
}

@Suite("Смысл не кодируется одним цветом")
struct MeaningNotByColourAloneTests {

    /// Каждый вид дня в календаре истории обязан иметь СВОЮ форму
    /// и СВОЁ слово.
    ///
    /// Дыра, ради которой сторож заведён: три вида дня отличались только
    /// оттенком точки в пять пунктов, а метка озвучки была датой и только
    /// датой. Для незрячего и для человека, не различающего красный
    /// и зелёный, экран «найди день, когда была кровь» не решался никак.
    @Test("У каждого вида дня свои значок и слово")
    func everyMarkerCarriesShapeAndWord() {
        let содержательные: [DayMarker] = [.ordinary, .alarm, .medical]

        for маркер in содержательные {
            #expect(маркер.symbol != nil, "у \(маркер) нет значка — останется один цвет")
            #expect(маркер.spoken != nil, "у \(маркер) нет слова — озвучка промолчит")
        }

        // Формы и слова обязаны РАЗЛИЧАТЬСЯ: три одинаковых значка
        // не лучше трёх одинаковых точек.
        #expect(Set(содержательные.compactMap(\.symbol)).count == содержательные.count,
                "значки повторяются")
        #expect(Set(содержательные.compactMap(\.spoken)).count == содержательные.count,
                "слова повторяются")

        // Пустой день молчит: выдумывать ему значок и слово было бы шумом.
        #expect(DayMarker.none.symbol == nil)
        #expect(DayMarker.none.spoken == nil)
    }
}
