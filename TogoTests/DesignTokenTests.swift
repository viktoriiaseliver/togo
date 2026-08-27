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
    private func components(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// WCAG относительная яркость — считаем сами, чтобы не тянуть зависимость.
    private func luminance(_ color: Color) -> Double {
        let (r, g, b) = components(color)
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
        #expect(contrast(Token.Ink.secondary, Token.Surface.screen) > 4.5)
    }

    @Test("Слабый текст проходит AA только для крупного кегля")
    func faintIsLargeTextOnly() {
        let ratio = contrast(Token.Ink.faint, Token.Surface.screen)
        #expect(ratio > 3)
        #expect(ratio < 4.5)
        // Поэтому в типографике micro — medium и минимум 12pt, а faint
        // назначается только стилям от 14pt.
        #expect(AppFont.caption.size >= 14)
    }

    @Test("Белый по кирпичу проходит AA")
    func brickButtonContrast() {
        // Прошлый брендинг был на охре, и белый по ней не проходил —
        // подпись главной кнопки приходилось делать чернильной.
        // Кирпич темнее, и белый на нём читается: 5,4:1.
        #expect(contrast(Token.Component.Button.Primary.label,
                         Token.Component.Button.Primary.background) > 4.5)
        #expect(Token.Component.Button.Primary.label == Token.Ink.onAccent)
    }

    @Test("Текст состояний читается на своём фоне")
    func statusContrast() {
        #expect(contrast(Token.Status.waitingText, Token.Status.waitingBg) > 4.5)
        #expect(contrast(Token.Status.overdueText, Token.Status.overdueBg) > 4.5)
        #expect(contrast(Token.Status.doneText, Token.Status.doneBg) > 4.5)
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

    @Test("Кирпичный текст читается на камне")
    func brickOnStone() {
        #expect(contrast(Token.Status.overdueText, Token.Surface.screen) >= 4.5)
    }

    @Test("Шалфейный текст читается на камне")
    func sageOnStone() {
        #expect(contrast(Token.Status.doneText, Token.Surface.screen) >= 4.5)
    }

    @Test("Горчица читается на своём тинте")
    func mustardOnTint() {
        #expect(contrast(Token.Status.waitingText, Token.Status.waitingBg) >= 4.5)
    }

    @Test("Белый читается на кирпичной заливке")
    func whiteOnBrick() {
        #expect(contrast(Token.Ink.onAccent, Token.Action.primary) >= 4.5)
    }

    @Test("Действие и «сделано» — разные цвета")
    func actionIsNotDone() {
        // Кирпич — одно главное действие на экран. Шалфей — норма
        // и навигация. Слить их значило бы потерять оба смысла.
        #expect(Token.Action.primary != Token.Action.done)
    }

    @Test("Горчица встречается ровно в одном месте")
    func mustardIsSingular() {
        // Единственный запрет в приложении — окно натощак.
        // Если этот цвет появится где-то ещё, запрет перестанет читаться.
        #expect(Token.Status.waitingText != Token.Action.primary)
        #expect(Token.Status.waitingText != Token.Action.done)
        #expect(Token.Status.waitingText != Token.Status.overdueText)
    }
}

@Suite("Брендинг · шрифт")
@MainActor
struct BrandFontTests {

    @Test("Onest вложен в приложение и зарегистрирован")
    func brandFontIsAvailable() {
        // Имя берётся из таблицы шрифта, а не из имени файла: iOS ищет
        // именно его, и опечатка здесь тихо откатывает всё на системный —
        // приложение при этом собирается и работает.
        #expect(UIFont(name: TextStyleToken.brandFont, size: 34) != nil)
    }

    @Test("Брендовый шрифт достаётся только крупным числам и вордмарку")
    func brandFontIsRare() {
        // «Onest 800 — только вордмарк и display 28px+». Если он утечёт
        // в строки и меты, брендом быть перестанет.
        #expect(AppFont.display.brand)
        #expect(AppFont.hero.brand)
        #expect(AppFont.wordmark.brand)

        #expect(!AppFont.body.brand)
        #expect(!AppFont.caption.brand)
        #expect(!AppFont.micro.brand)
        #expect(!AppFont.screenTitle.brand)
        #expect(!AppFont.cardTitle.brand)
        #expect(!AppFont.numeric(17).brand)
    }

    @Test("Крупные числа и правда крупные")
    func brandSizesAreLarge() {
        #expect(AppFont.display.size >= 28)
        #expect(AppFont.hero.size >= 28)
    }
}
