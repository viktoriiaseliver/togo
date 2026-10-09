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
    /// **Ни один токен, проваливающий порог, не красит передний план.**
    ///
    /// Список запрещённых НЕ написан руками — он вычисляется замером.
    /// Прежняя редакция запрещала `Ink.faint` поимённо, и этого хватило
    /// ровно на одну ошибку: рядом жил `Action.done` — мятный ТИНТ 14 %,
    /// которым красили живой текст в двадцати местах, включая «в норме»
    /// на экране здоровья. Он даёт **1,3:1** — вдвое хуже запрещённого
    /// faint, и запрет по имени его не видел.
    ///
    /// Корень один и тот же: **заливочный токен, применённый как
    /// чернила**. Ловить его надо по свойству, а не по имени, иначе
    /// сторож будет всегда на одну ошибку позади.
    @Test("Токен, не берущий порог, не красит передний план")
    func failingTokensAreNeverForegroundColours() throws {
        // Имя токена в коде → его цвет. Список закрытый и потому честный:
        // новый токен придётся добавить сюда руками, и это правильно —
        // иначе он приедет непроверенным.
        let токены: [(String, Color)] = [
            ("Ink.faint", Token.Ink.faint),
            ("Ink.secondary", Token.Ink.secondary),
            ("Ink.silhouette", Token.Ink.silhouette),
            ("Action.done", Token.Action.done),
            ("Action.doneQuiet", Token.Action.doneQuiet),
            ("Action.doneText", Token.Action.doneText),
            ("Action.primary", Token.Action.primary),
            ("Action.primaryQuiet", Token.Action.primaryQuiet),
            ("Action.secondary", Token.Action.secondary),
            ("Status.waitingText", Token.Status.waitingText),
            ("Status.overdueText", Token.Status.overdueText),
        ]

        // Проваливает порог хоть на одной поверхности — значит текстом
        // не красится нигде: человек не выбирает, на какой поверхности
        // окажется строка.
        //
        // `Ink.onAccent` в список не входит и не должен: он и описан как
        // «текст на мятной ЗАЛИВКЕ», то есть его фон — не поверхность
        // экрана, и мерить его здешними поверхностями значит спрашивать
        // не про то место.
        let запрещённые = токены
            .filter { имя, цвет in
                имя != "Ink.onAccent"
                    && Self.surfaces.contains { Contrast.ratio(цвет, on: $0.1) < 4.5 }
            }
            .map(\.0)

        #expect(!запрещённые.isEmpty, "замер перестал находить слабые токены — проверь формулу")

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

                for вызов in Self.foregroundCalls(in: текст) {
                    for имя in запрещённые where Self.mentions("Token.\(имя)", in: вызов.аргумент) {
                        найдено.append("\(файл.lastPathComponent):\(вызов.строка) — \(имя) — \(вызов.аргумент.prefix(80))")
                    }
                }
            }
        }

        #expect(
            найдено.isEmpty,
            """
            передним планом красит токен, не берущий 4,5:1 \
            (проваливают: \(запрещённые.joined(separator: ", "))):
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

    /// Упоминается ли токен ЦЕЛИКОМ, а не как начало другого имени.
    ///
    /// Первый прогон этого сторожа дал тридцать ложных тревог, и все
    /// тридцать — из-за подстроки: `Token.Action.done` — начало
    /// `Token.Action.doneText`, то есть запрещённым оказывался ровно тот
    /// токен, которым дефект и починили. Имя обязано кончаться там, где
    /// кончается: следом должна идти не буква.
    nonisolated static func mentions(_ имя: String, in текст: String) -> Bool {
        var срез = текст[текст.startIndex...]
        while let найдено = срез.range(of: имя) {
            let следующий = найдено.upperBound
            let буква = следующий < срез.endIndex
                && (срез[следующий].isLetter || срез[следующий].isNumber)
            if !буква { return true }
            срез = срез[следующий...]
        }
        return false
    }

    /// Аргументы вызовов, красящих ПЕРЕДНИЙ ПЛАН, — со скобочным разбором.
    ///
    /// Первая редакция сторожа искала запрещённый токен по строке, и это
    /// была та же ошибка, что она ловит, только зеркальная: она проверяла
    /// ВЕЛИЧИНУ, не глядя на МЕСТО. Десять ложных тревог подряд — заливки
    /// `.fill(…)`, `.background(…)` и тинты аватарки, где бледный цвет
    /// как раз и нужен. Ложная тревога не лучше ложного спокойствия:
    /// сторож, который кричит зря, выключают.
    ///
    /// Поэтому берётся аргумент вызова целиком, со счётом скобок: так
    /// тройной оператор внутри `foregroundStyle` виден, даже если он
    /// разложен на три строки, а соседний `.fill` — не виден вовсе.
    ///
    /// Чего приём не покрывает и врать про это нельзя: цвет, положенный
    /// в переменную и применённый строкой ниже. Такие места ловит только
    /// чтение глазами.
    nonisolated static func foregroundCalls(in текст: String) -> [(строка: Int, аргумент: String)] {
        let символы = Array(текст)
        var результат: [(Int, String)] = []
        for приём in ["foregroundStyle(", ".color("] {
            let образец = Array(приём)
            var i = 0
            while i + образец.count < символы.count {
                guard Array(символы[i..<(i + образец.count)]) == образец else { i += 1; continue }
                var глубина = 1
                var j = i + образец.count
                var аргумент = ""
                while j < символы.count && глубина > 0 {
                    let c = символы[j]
                    if c == "(" { глубина += 1 }
                    if c == ")" { глубина -= 1; if глубина == 0 { break } }
                    аргумент.append(c)
                    j += 1
                }
                let номер = символы[0..<i].filter { $0 == "\n" }.count + 1
                результат.append((номер, аргумент.replacingOccurrences(of: "\n", with: " ")))
                i = j
            }
        }
        return результат
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

    /// Составляющие цвета **в тёмной теме, закреплённой явно.**
    ///
    /// Прежняя редакция звала `UIColor(colour).getRed(…)` — то есть
    /// брала значение по `UITraitCollection.current`, какой бы та
    /// ни была. У модульного прогона окна приложения нет, текущая
    /// коллекция в нём не тёмная, а токены с 07.10.2026
    /// **четырёхрежимные**. Приложение при этом тёмное и только тёмное.
    ///
    /// **Цена была не в точности, а в ложной находке.** Список
    /// запрещённых здесь **вычисляется** (`Contrast.ratio(…) < 4.5`)
    /// по тем же динамическим токенам — и янтарь попадал в него
    /// по светлой поверхности:
    ///
    /// ```
    /// Status.waitingText #F7C75F  на экране   #050503   12,91:1  берёт
    ///                             на карточке #181818   11,24:1  берёт
    ///                             на БЕЛОЙ    #FFFFFF    1,58:1  нет
    /// ```
    ///
    /// > **Сторож предъявлял семь ЗАКОННЫХ мест показа в тёмном
    /// > приложении** (`TodayScreen:208`, `HealthScreen:273` и пять
    /// > остальных) — и заслонял при этом живую жалобу человека
    /// > «не виден текст» из отзыва на сборку 273. Девять ложных
    /// > находок хуже одной пропущенной: после них сторожа перестают
    /// > читать.
    ///
    /// Разрешитель НЕ свой: `Color.resolvedHex(dark:highContrast:)`
    /// заведён как вход для приёмки и уже зовётся двумя тестами.
    /// Альфу он отдаёт младшим байтом — она здесь нужна, `ratio`
    /// смешивает по ней.
    private static func components(_ colour: Color) -> (Double, Double, Double, Double) {
        let rgba = colour.resolvedHex(dark: true, highContrast: false)
        func канал(_ сдвиг: UInt32) -> Double {
            Double((rgba >> сдвиг) & 0xFF) / 255
        }
        return (канал(24), канал(16), канал(8), канал(0))
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
