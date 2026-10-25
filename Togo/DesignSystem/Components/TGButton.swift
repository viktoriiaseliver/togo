import SwiftUI

/// Figma: `Button`. Свойства компонента один в один — `variant`, `size`,
/// `icon`, `fullWidth`, состояние `disabled`.
///
/// Правило макета зашито в варианты: охряная заливка есть только у `.primary`,
/// и на экране такая кнопка должна быть одна.
struct TGButton: View {
    /// Вариант — это про смысл действия, а не про цвет.
    ///
    /// Правило брендинга: **кирпич — ровно одно главное действие
    /// на экран.** Если кирпича на экране два, один из них лишний.
    /// Горчица занята окном натощак и больше нигде не появляется —
    /// поэтому отдельного «приостановить» цветом нет: пауза обратима
    /// и ничего не записывает, ей хватает камня.
    enum Variant: String, CaseIterable, Sendable {
        /// Главное действие экрана. На экране оно одно.
        case primary
        /// Второй путь: тоже нормальный, но не основной.
        case secondary
        /// Завершает начатое: занятие, эпизод. Шалфей — тот же, которым
        /// помечено «сделано» и «норма».
        case finish
        /// Без фона. Для действий, которые не должны спорить за внимание.
        case quiet
        /// Убирает данные. Терракот — и только он.
        case destructive
    }

    enum Size: String, CaseIterable, Sendable {
        case large
        case medium

        var height: CGFloat {
            switch self {
            case .large: Token.Component.Button.Primary.height
            case .medium: Token.Component.Button.Secondary.height
            }
        }

        var style: TextStyleToken {
            switch self {
            case .large: AppFont.cardTitle
            case .medium: AppFont.bodyEmphasis
            }
        }
    }

    let title: LocalizedStringKey
    var variant: Variant = .primary
    var size: Size = .large
    /// Иконка — имя SF Symbol. Своих растровых иконок в приложении нет.
    var systemImage: String?
    var fullWidth: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .multilineTextAlignment(.center)
                    // Длинная подпись переносится, а кнопка становится выше.
                    // Ужимать текст на главном действии нельзя.
                    .wraps()
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
            }
            .labelStyle(TGButtonLabelStyle(hasIcon: systemImage != nil))
            .font(size.style.font)
            .padding(.vertical, Token.Space.s8)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
            .padding(.horizontal, fullWidth ? Token.Space.s12 : Token.Space.s20)
        }
        .buttonStyle(TGButtonStyle(variant: variant, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

/// Иконка и подпись всегда в одном ряду с фиксированным зазором.
private struct TGButtonLabelStyle: LabelStyle {
    let hasIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: hasIcon ? Token.Space.s8 : 0) {
            configuration.icon
            configuration.title
        }
    }
}

/// Здесь и только здесь варианты превращаются в токены.
struct TGButtonStyle: ButtonStyle {
    let variant: TGButton.Variant
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
            .overlay {
                // ВТОРОСТЕПЕННУЮ КНОПКУ НЕ ВИДНО ВОВСЕ (замер 25.10.2026).
                //
                // `Button.Secondary.background` (`night4`) и `Surface.screen`
                // (`night1`) равны **байт в байт** в светлой теме, а в тёмной
                // не дотягивают до порога границы органа:
                //
                // ```
                // режим      заливка/экран   с этой обводкой
                // light         1,0000:1  →     6,62:1
                // lightHC       1,0000:1  →     9,19:1
                // dark          1,8504:1  →     6,74:1
                // darkHC        2,3014:1  →     7,68:1
                // порог WCAG 1.4.11 для границы органа — 3:1
                // ```
                //
                // **Порога не брал НИ ОДИН из четырёх режимов**, а не только
                // светлые: запись в эталоне считала тёмную исправной, потому
                // что мерила «видно ли плашку», а не порог. Подпись при этом
                // держит 18,90:1 — слово человек читает прекрасно, он
                // не видит КНОПКУ. Вызовов `.secondary` сегодня тридцать;
                // в эталоне записано десять, замер от 15.10.
                //
                // # Почему обводка, а не новый цвет заливки
                //
                // Значение цвета — решение Виктории, и эталон называет три
                // пути: своё значение в нейтральной рампе, обводка, подъём
                // только `lightHC`. Выбрана обводка **существующим токеном**:
                // она не выдумывает ни одного значения, то есть не выдаёт
                // придуманное за принятое. Третий путь не годится — он
                // оставил бы кнопку невидимой в обычной светлой теме,
                // а именно её человек видит чаще всего.
                //
                // Перевести заливку на `night5` вслед за выключенной нельзя:
                // второстепенная и выключенная стали бы одного цвета, и на
                // это уже стоит сторож `ThemeContrastTests`.
                //
                // # Чего это НЕ закрывает
                //
                // Сторож `ПовышенныйКонтрастМеняетЦветTests` останется
                // красным: его ось — равенство байт у двух ЗАЛИВОК, и обводку
                // он не видит вовсе (сказано в самой записи эталона). Снимать
                // запись надо по КАДРУ, а не по тесту, и кадра пока нет.
                if variant == .secondary, isEnabled {
                    RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                        .strokeBorder(Token.Ink.secondary, lineWidth: Token.Size.hairline)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: Token.Duration.instant), value: configuration.isPressed)
    }

    private var background: Color {
        guard isEnabled else { return Token.Component.Button.Disabled.background }
        switch variant {
        case .primary: return Token.Component.Button.Primary.background
        case .secondary: return Token.Component.Button.Secondary.background
        case .finish: return Token.Component.Button.Finish.background
        case .quiet: return .clear
        case .destructive: return Token.Component.Button.Destructive.background
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Token.Component.Button.Disabled.label }
        switch variant {
        case .primary: return Token.Component.Button.Primary.label
        case .secondary: return Token.Component.Button.Secondary.label
        case .finish: return Token.Component.Button.Finish.label
        case .quiet: return Token.Ink.secondary
        case .destructive: return Token.Component.Button.Destructive.label
        }
    }
}

/// Figma: `StepButton`. Круглая кнопка «плюс/минус» рядом с числом.
struct TGStepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Token.Size.iconLg, weight: .semibold))
                .foregroundStyle(Token.Ink.primary)
                .frame(width: Token.Size.controlXL, height: Token.Size.controlXL)
                .background(Token.Surface.sunken, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Больше" : "Меньше")
    }
}

/// Figma: `Stepper`. Число с двумя круглыми кнопками — родитель для `StepButton`.
struct TGStepper: View {
    @Binding var value: Int
    let unit: LocalizedStringKey
    var step: Int = 1
    var range: ClosedRange<Int> = 0...999
    /// Внутри строки, а не на весь экран: в правке записи шаговик стоит
    /// справа от подписи и не имеет права быть крупнее самой строки.
    var compact: Bool = false

    var body: some View {
        if compact { inline } else { full }
    }

    private var full: some View {
        HStack(spacing: Token.Space.s20) {
            TGStepButton(symbol: "minus") { adjust(-step) }
            VStack(spacing: 0) {
                Text("\(value)").textStyle(AppFont.hero)
                Text(unit).textStyle(AppFont.caption)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text("\(value) ") + Text(unit))
            TGStepButton(symbol: "plus") { adjust(step) }
        }
        .frame(maxWidth: .infinity)
    }

    private var inline: some View {
        HStack(spacing: Token.Space.s12) {
            TGStepButton(symbol: "minus") { adjust(-step) }
            (Text(verbatim: "\(value) ") + Text(unit))
                .textStyle(AppFont.numeric(17))
                .frame(minWidth: 64)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text("\(value) ") + Text(unit))
            TGStepButton(symbol: "plus") { adjust(step) }
        }
    }

    private func adjust(_ delta: Int) {
        value = min(range.upperBound, max(range.lowerBound, value + delta))
        Haptics.tap()
    }
}
