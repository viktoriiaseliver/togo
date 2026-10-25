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
        // Цвет выключенного контрола. Читать им ничего нельзя, и ни один
        // текстовый стиль его по умолчанию не берёт: подписи идут вторичным.
        //
        // # УТВЕРЖДЕНИЕ ПРО КОНТРАСТ СНЯТО 25.10.2026 — РЕШЕНИЕ ДИЗАЙНА
        //
        // Стояло `#expect(faint < 4.5)`. Снято ответом дизайна, круг 6,
        // пункт 7, дословно: «Утверждение „не проходит контраст" снять
        // с причиной „значение сменилось, 6,44:1". Запрет на текстовые
        // стили оставить».
        //
        // Причина названа, и она не про порог. В теме «Кино» ОБЕ
        // ПОЛОВИНЫ контраста двинулись в одну сторону — чернила
        // посветлели, фон потемнел, — и `faint` взял порог:
        //
        // ```
        // экран       6,44 (было 3,94 в Graphite 21.10)
        // карточка    5,22 (было 3,43)
        // утопленное  4,27 (было 3,19)  ← ниже порога ДО СИХ ПОР
        // ```
        //
        // **Замер был верен, а ось отвечала не на то.** Она обосновывала
        // правило «этим цветом текст не красят» ЧИСЛОМ, которым правило
        // когда-то вывели, и число перестало быть верным раньше правила.
        //
        // > **Правило живо и окрепло по смыслу:** в пакете «Кино» этот
        // > токен НАЗВАН `text.disabled`, цветом недоступного, и живой
        // > текст в нём читался бы как выключенный даже там, где
        // > контраста хватает. Тихий живой текст — `text.secondary`
        // > (то же слово дизайна).
        //
        // Правка порога под текущее число (`< 7` вместо `< 4.5`) НЕ была
        // бы ни одним из двух исходов: это дыра ровно того размера.
        // Поэтому ось не правится, а СНИМАЕТСЯ — вместе с причиной.
        //
        // Вторая половина набора остаётся и держит ровно правило.
        for style in [AppFont.micro, AppFont.caption, AppFont.caps,
                      AppFont.body, AppFont.cardTitle] {
            #expect(style.color != Token.Ink.faint, """
                стиль берёт `Ink.faint` цветом текста. Это цвет
                НЕДОСТУПНОГО (`text.disabled` в пакете «Кино»), и живой
                текст в нём читается как выключенный независимо от того,
                сколько у него контраста. Тихий живой текст —
                `Ink.secondary`.
                """)
        }
    }

    /// Контроль к снятому утверждению: `faint` правда стал контрастным.
    ///
    /// Без него «утверждение сняли» неотличимо от «утверждение
    /// забыли»: следующий прочтёт снятую ось и не узнает, на каком
    /// числе её снимали. Здесь это число ЖИВЁТ и проверяется — если
    /// палитра поедет обратно, набор скажет об этом прежде, чем
    /// кто-нибудь успеет вернуть порог «потому что опять не проходит».
    @Test("Контроль: faint взял порог на экране, и ось снята не напрасно")
    func faintВзялПорог() {
        let наЭкране = contrast(over(Token.Ink.faint, on: Token.Surface.screen),
                                Token.Surface.screen)
        #expect(наЭкране > 4.5, """
            `Ink.faint` на экране даёт \(String(format: "%.2f", наЭкране)),
            то есть порога больше НЕ берёт — а утверждение про контраст
            снято 25.10.2026 именно потому, что он его взял (6,44).
            Палитра поехала назад. Возвращать порог нельзя: правило
            держится смыслом (`text.disabled` — цвет недоступного),
            и ось была снята сознательно. Это вопрос к дизайну.
            """)

        // И то, что дизайн не называл, а счёт показывает: на УТОПЛЕННОЙ
        // области порога по-прежнему нет. Печатается всегда, потому что
        // «запрет испарился» — неверный вывод; верно «основание
        // сузилось втрое».
        let наУтопленном = contrast(over(Token.Ink.faint, on: Token.Surface.sunken),
                                    Token.Surface.sunken)
        print("""
            FAINT · экран \(String(format: "%.2f", наЭкране)) · \
            утопленное \(String(format: "%.2f", наУтопленном)). \
            На утопленном порога нет и сегодня — запрет не «испарился», \
            у него сузилось основание.
            """)
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

    @Test("У каждой яркой роли один токен, и роли не делят его")
    func brightRolesDoNotShareTokens() {
        // ПЕРЕИМЕНОВАНО 07.10.2026, тело не тронуто. «Ровно два» было
        // про лайм с янтарём; тело цвета не считает — все четыре
        // утверждения сравнивают ТОКЕНЫ между собой.
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

    @Test("Акцент — только интерактив, «сделано» — плашка")
    func accentIsInteractiveOnly() {
        // ПЕРЕИМЕНОВАНО 07.10.2026, тело не тронуто. Имя говорило про
        // МЯТУ, которой в палитре больше нет: поколение Graphite,
        // акцент индиго. Тело же не упоминает ни мяту, ни цвет вовсе —
        // оно проверяет РАЗДЕЛЕНИЕ РОЛЕЙ, и это правило в силе при любом
        // поколении.
        //
        // Снять было нельзя: дыра, про которую никто не вспомнит.
        // Править логику незачем: она не про цвет. У нас записано, чем
        // кончается устаревшее имя — его читают ВМЕСТО кода, и гревший
        // по имени получает обратную историю (Gamut,
        // `…AddingLeadsToPaywall`, пять дней).
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
        let signals = [Token.Action.primary, Token.Action.doneText,
                       Token.Status.waitingText, Token.Status.overdueText]
        #expect(Set(signals.map(String.init(describing:))).count == signals.count)
    }

    @Test("Радиусы лежат на шкале 12 · 16 · 18 · 20 · 30 · 40")
    func radiiOnScale() {
        // Ядро Graphite (GRAPHITE.md, «Форма и отступы»), 05.10.2026:
        // шит 36 · карточка 28 · строка 24 · вложенные 16 · пилюля 999.
        // Двенадцать осталось: ядро его не задаёт числом, а ВЫВОДИТ —
        // «вложенный = внешний − padding», строка 24 с полем 12 даёт 12.
        //
        // ЭТОТ СТОРОЖ ВТОРОЙ, и он остался непереведённым, когда перевели
        // первый (StructuralGapsTests, 9c07321). Сторожей метрик два,
        // правка села на одну поверхность из двух — тот самый класс,
        // который в этом проекте оплачен тремя поверхностями отсчёта.
        // Поймал togo-45 ПРОГОНОМ, а не чтением: читая, я был уверен,
        // что перевёл всё.
        let scale: Set<CGFloat> = [12, 16, 24, 28, 36, 999]
        for radius in [Token.Radius.small, Token.Radius.control,
                       Token.Radius.tile, Token.Radius.card,
                       Token.Radius.sheet, Token.Radius.capsule] {
            #expect(scale.contains(radius))
        }
    }

    @Test("Сигналов ровно четыре, и они не совпадают")
    func threeSignals() {
        // «Лёд» развёл то, что мята держала вместе. Синий — интерактив
        // и «сейчас». Хвойный — «сделано». Янтарь — подожди. Красный —
        // плохое. Больше цветов система не выдаёт.
        //
        // Прежде сигналов было три, потому что «нажми» и «готово» сидели
        // на одном мятном значении: одно и то же слово отвечало на два
        // разных вопроса.
        #expect(Token.Action.primary != Token.Action.doneText)
        #expect(Token.Action.doneText != Token.Status.waitingText)
        #expect(Token.Action.doneText != Token.Status.overdueText)
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
