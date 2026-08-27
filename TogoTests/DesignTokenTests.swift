import Testing
import SwiftUI
import UIKit
@testable import Togo

/// Токены нельзя править в Swift руками: источник — DesignTokens/tokens.json.
/// Эти тесты ловят ровно то, что легко сломать вручную, и держат контракт
/// с Figma: одно значение — одна роль.
@Suite("Дизайн-токены")
@MainActor
struct DesignTokenTests {
    private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Наложить полупрозрачный цвет на плотную поверхность.
    ///
    /// В тёмной системе половина токенов задана долей белого или тинтом
    /// в четырнадцать процентов. Считать их контраст «как есть»
    /// бессмысленно: прозрачный цвет сам по себе не читается ни на чём,
    /// и проверка молча возвращала единицу.
    private func over(_ color: Color, on base: Color) -> Color {
        let top = components(color), bottom = components(base)
        return Color(.sRGB,
                     red: top.r * top.a + bottom.r * (1 - top.a),
                     green: top.g * top.a + bottom.g * (1 - top.a),
                     blue: top.b * top.a + bottom.b * (1 - top.a),
                     opacity: 1)
    }

    /// WCAG относительная яркость — считаем сами, чтобы не тянуть зависимость.
    private func luminance(_ color: Color) -> Double {
        let (r, g, b, _) = components(color)
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ lhs: Color, _ rhs: Color) -> Double {
        let a = luminance(lhs), b = luminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test("Чернила на бумаге проходят AAA")
    func inkContrast() {
        #expect(contrast(Token.Ink.primary, Token.Surface.screen) > 7)
    }

    @Test("Вторичный текст проходит AA")
    func secondaryContrast() {
        #expect(contrast(over(Token.Ink.secondary, on: Token.Surface.screen),
                         Token.Surface.screen) > 4.5)
    }

    @Test("Слабый серый означает «выключено», а не тихий текст")
    func faintIsOffState() {
        // В тёмной системе это тридцать процентов белого — по спецификации
        // цвет выключенного контрола. Читать им ничего нельзя, и ни один
        // текстовый стиль его по умолчанию не берёт: подписи идут
        // вторичным, шестьдесят процентов.
        let faint = contrast(over(Token.Ink.faint, on: Token.Surface.screen),
                             Token.Surface.screen)
        #expect(faint < 3)

        for style in [AppFont.micro, AppFont.caption, AppFont.caps,
                      AppFont.body, AppFont.cardTitle] {
            #expect(style.color != Token.Ink.faint)
        }
    }

    @Test("Подпись главной кнопки читается на заливке")
    func primaryButtonContrast() {
        #expect(contrast(Token.Component.Button.Primary.label,
                         Token.Component.Button.Primary.background) > 4.5)
        #expect(Token.Component.Button.Primary.label == Token.Ink.onAccent)
    }

    @Test("Сигнал читается на поверхности, а подпись плашки — белая")
    func statusContrast() {
        // Так это и меряет аудит: сигнальный цвет живёт на угле,
        // а не на собственном тинте. На своей плашке он проваливается
        // ниже порога, поэтому подписи там белые, а цвет — у иконки.
        #expect(contrast(Token.Status.waitingText, Token.Surface.card) > 4.5)
        #expect(contrast(Token.Status.overdueText, Token.Surface.card) > 4.5)

        func onCard(_ tint: Color) -> Color { over(tint, on: Token.Surface.card) }
        #expect(contrast(Token.Ink.primary, onCard(Token.Status.overdueBg)) > 4.5)
        #expect(contrast(Token.Ink.primary, onCard(Token.Status.waitingBg)) > 4.5)
        #expect(contrast(Token.Status.doneText, onCard(Token.Status.doneBg)) > 4.5)
    }

    @Test("Ярких цветов ровно два, и у каждого одна роль")
    func exactlyTwoAccents() {
        // Охра — только действие и «сейчас». Сине-зелёный — только «сделано».
        #expect(Token.Component.Button.Primary.background == Token.Action.primary)
        #expect(Token.Component.Timeline.nowMarker == Token.Action.primary)
        #expect(Token.Component.Timeline.syncedMark == Token.Action.done)
        // Светлая охра идёт под плашки и никогда под кнопку.
        #expect(Token.Component.Button.Primary.background != Token.Action.primaryQuiet)
    }

    @Test("Цели нажатия не меньше 44pt")
    func tapTargets() {
        #expect(Token.Size.tapTarget >= 44)
        #expect(Token.Component.Button.Primary.height >= 44)
        #expect(Token.Component.Button.Secondary.height >= 44)
        #expect(Token.Component.Chip.height >= 44)
    }

    @Test("Ручка шторки одна на всё приложение: 36×4")
    func sheetHandle() {
        #expect(Token.Component.Sheet.handleWidth == 36)
        #expect(Token.Component.Sheet.handleHeight == 4)
    }

    @Test("Плашка натощак крупнее обычного текста — её нельзя проскроллить незаметно")
    func bannerTitleIsBigEnough() {
        #expect(Token.Component.Banner.titleSize >= Token.FontSize.section)
        #expect(Token.Component.Banner.titleSize > Token.FontSize.body)
    }
}

// MARK: - Брендинг «кирпич и шалфей»

@Suite("Брендинг · роли цвета")
@MainActor
struct BrandRoleTests {

    /// Контрасты назвал дизайнер и проверил их сам; тест держит их
    /// от тихого сползания при следующей правке палитры.
    private func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let parts = UIColor(color).cgColor.components ?? [0, 0, 0, 1]
            let rgb = parts.count >= 3 ? Array(parts.prefix(3)) : [parts[0], parts[0], parts[0]]
            let linear = rgb.map { channel -> Double in
                let value = Double(channel)
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    @Test("Сигнальный текст читается на карточке")
    func signalsOnCard() {
        #expect(contrast(Token.Status.doneText, Token.Surface.card) >= 4.5)
        #expect(contrast(Token.Status.waitingText, Token.Surface.card) >= 4.5)
        #expect(contrast(Token.Status.overdueText, Token.Surface.card) >= 4.5)
    }

    @Test("Тёмный текст читается на мятной заливке")
    func inkOnMint() {
        #expect(contrast(Token.Ink.onAccent, Token.Action.primary) >= 4.5)
    }

    @Test("Полная мята — только интерактив")
    func mintIsInteractiveOnly() {
        // Аудит цвета поймал двойную роль: на одном экране кнопка
        // и галочка выполненного читались одинаково активными.
        // «Сделано» — плашка с белой галочкой, а не заливка.
        #expect(Token.Action.primary != Token.Action.done)
        #expect(Token.Status.doneText == Token.Ink.primary)
    }

    @Test("Одно значение на роль")
    func oneValuePerRole() {
        // Находка аудита: сто тридцать восемь значений цвета на файл,
        // из них три разные мяты. Системе хватает двадцати токенов,
        // остальное — дрейф: одна роль, записанная чуть по-разному.
        let signals = [Token.Action.primary, Token.Status.waitingText,
                       Token.Status.overdueText]
        #expect(Set(signals.map(String.init(describing:))).count == signals.count)
    }

    @Test("Радиусы лежат на шкале 12 · 16 · 20 · 26")
    func radiiOnScale() {
        let scale: Set<CGFloat> = [12, 16, 20, 26]
        for radius in [Token.Radius.small, Token.Radius.control,
                       Token.Radius.tile, Token.Radius.card] {
            #expect(scale.contains(radius))
        }
    }

    @Test("Сигналов ровно три, и они не совпадают")
    func threeSignals() {
        // Мята — действие и норма. Жёлтый — подожди. Красный — плохое.
        // Больше цветов система не выдаёт.
        #expect(Token.Action.primary != Token.Status.waitingText)
        #expect(Token.Action.primary != Token.Status.overdueText)
        #expect(Token.Status.waitingText != Token.Status.overdueText)
    }

    @Test("Ниже четырнадцати кеглей не существует")
    func noTypeBelowFourteen() {
        for style in [AppFont.micro, AppFont.caption, AppFont.captionEmphasis,
                      AppFont.caps, AppFont.body, AppFont.cardTitle] {
            #expect(style.size >= 14)
        }
    }

    @Test("Герой крупнее всего остального")
    func heroIsLargest() {
        // Один герой на экран крупной цифрой, всё остальное на два шага
        // тише — иначе иерархии нет и экран читается ровным серым.
        #expect(AppFont.hero.size > AppFont.display.size)
        #expect(AppFont.display.size > AppFont.sectionTitle.size)
    }
}
