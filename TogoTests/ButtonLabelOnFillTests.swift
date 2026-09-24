import Testing
import Foundation
import SwiftUI
@testable import Togo

/// Подпись на заливке главной кнопки.
///
/// Дефект, ради которого сторож заведён, прожил обе палитры и был
/// невидим для проверок. `BigAction` красил подпись `Token.Ink.primary`
/// в обоих вариантах, а заливку переключал: тёмная у второстепенной,
/// светлая у главной. Светлый текст на светлой заливке — белый на мяте
/// давал **1,68:1**, светлый на синем «Льда» — **1,98:1**.
///
/// Почему это не поймали:
///
/// - `DesignTokenTests.primaryButtonContrast` проверял, что
///   `Component.Button.Primary.label == Ink.onAccent` и что их контраст
///   больше 4,5. Токен всё это время был **верен**. Экран его не звал —
///   тест проверял модель, а не вызов;
/// - кадры снимались, но подпись читали глазом, а глаз соглашается
///   с тем, что привык видеть. Нашлось замером пикселя на кадре.
///
/// Поэтому здесь два сторожа сразу: один на **значения** токенов,
/// другой на **вызов** из экрана. Первый молчал бы и при этом дефекте,
/// второй — при неверном токене.
@Suite("Подпись читается на своей заливке")
struct ButtonLabelOnFillTests {

    // MARK: - Сторож на значения

    private func яркость(_ цвет: Color) -> Double {
        let c = UIColor(цвет).cgColor.components ?? []
        guard c.count >= 3 else { return 0 }
        func s(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * s(c[0]) + 0.7152 * s(c[1]) + 0.0722 * s(c[2])
    }

    private func контраст(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (яркость(a), яркость(b))
        let (hi, lo) = (max(x, y), min(x, y))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test("У каждой кнопки подпись читается на своей заливке")
    func каждаяПараПроходит() {
        // Именно пара «подпись поверх СВОЕЙ заливки», а не подпись
        // поверх экрана: заливка и есть фон, на котором человек читает.
        let пары: [(String, Color, Color)] = [
            ("primary", Token.Component.Button.Primary.label,
             Token.Component.Button.Primary.background),
            ("secondary", Token.Component.Button.Secondary.label,
             Token.Component.Button.Secondary.background),
            ("destructive", Token.Component.Button.Destructive.label,
             Token.Component.Button.Destructive.background),
        ]
        for (имя, подпись, заливка) in пары {
            #expect(контраст(подпись, заливка) >= 4.5, """
                подпись кнопки «\(имя)» даёт \
                \(String(format: "%.2f", контраст(подпись, заливка))):1 \
                на своей заливке. Ниже 4,5 — значит её не прочитают.
                """)
        }
        // Счётчик осмотренного: пустой список прошёл бы цикл молча.
        #expect(пары.count == 3)
    }

    // MARK: - Сторож на вызов

    private func исходник(_ путь: String) throws -> String {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: корень.appendingPathComponent(путь), encoding: .utf8)
    }

    /// Комментарии вырезаются до разбора. Иначе сторож меряет прозу:
    /// прямо над правкой в `ActionGrid` стоит объяснение, в котором
    /// `Token.Ink.primary` упомянут как то, чего делать нельзя.
    private func безКомментариев(_ текст: String) -> String {
        текст.split(separator: "\n", omittingEmptySubsequences: false)
            .map { строка -> String in
                guard let i = строка.range(of: "//") else { return String(строка) }
                return String(строка[строка.startIndex..<i.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// Тело одного типа, а не весь файл.
    ///
    /// Первая редакция этого сторожа запрещала `Ink.primary` во всём
    /// `ActionGrid.swift` и покраснела сразу — на `SmallAction`, где
    /// он **верен**: плитки «Стул · Еда · Инцидент» лежат на тёмной
    /// заливке. Запрет, срабатывающий на здоровом коде, учит не верить
    /// красному, и это дороже пропущенного дефекта.
    private func тело(_ тип: String, в код: String) -> String {
        guard let начало = код.range(of: "struct \(тип): View {") else { return "" }
        let хвост = код[начало.upperBound...]
        guard let конец = хвост.range(of: "\nstruct ") else { return String(хвост) }
        return String(хвост[..<конец.lowerBound])
    }

    @Test("Главная кнопка берёт подпись у компонентного токена")
    func подписьИзТокена() throws {
        let код = безКомментариев(try исходник("Togo/Features/Today/ActionGrid.swift"))
        let большая = тело("BigAction", в: код)

        #expect(!большая.isEmpty, "тело BigAction не найдено — сторож смотрит в пустоту")

        #expect(большая.contains("Token.Component.Button.Primary.label"), """
            BigAction перестал звать Component.Button.Primary.label.
            Значит подпись на синей заливке снова собирается на месте,
            а не берётся у системы — так она и оказалась 1,98:1.
            """)

        // Ровно то, что было: один светлый цвет на оба варианта.
        #expect(!большая.contains(".foregroundStyle(Token.Ink.primary)"), """
            подпись BigAction снова красится Ink.primary без разбора
            варианта. На тёмной заливке это верно, на светлой — нет.
            """)
    }

    @Test("Вырезание тела не хватает лишнего")
    func телоВырезаетсяТочно() throws {
        // У SmallAction Ink.primary законен: плитки тёмные. Если
        // вырезание захватит соседа, сторож покраснеет на здоровом коде.
        let код = безКомментариев(try исходник("Togo/Features/Today/ActionGrid.swift"))
        let малая = тело("SmallAction", в: код)
        #expect(!малая.isEmpty)
        #expect(малая.contains(".foregroundStyle(Token.Ink.primary)"),
                "SmallAction перестал красить подпись Ink.primary — проверь, не уехал ли дефект туда")
        #expect(!тело("BigAction", в: код).contains("struct SmallAction"),
                "вырезание тела BigAction захватило соседний тип")
    }

    @Test("Сканер видит файл и находит в нём вызовы — иначе он молчит зря")
    func сканерНеПустой() throws {
        // Сканер, переставший что-либо находить, молчит так же, как тот,
        // кому нечего сказать. Проверяем, что файл прочитан и не пуст.
        let код = безКомментариев(try исходник("Togo/Features/Today/ActionGrid.swift"))
        #expect(код.count > 1000, "исходник ActionGrid прочитан пустым или укоротился вдвое")
        #expect(код.contains("struct BigAction"), "BigAction переименован или уехал из файла")
    }

    @Test("Вырезание комментариев работает")
    func комментарииВырезаются() {
        let проба = """
            let a = 1 // Token.Ink.primary тут только в прозе
            let b = 2
            """
        let чисто = безКомментариев(проба)
        #expect(!чисто.contains("Token.Ink.primary"))
        #expect(чисто.contains("let a = 1"))
        #expect(чисто.contains("let b = 2"))
    }
}
