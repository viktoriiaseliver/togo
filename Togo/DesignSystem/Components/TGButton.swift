import SwiftUI

/// Figma: `Button`. Свойства компонента один в один — `variant`, `size`,
/// `icon`, `fullWidth`, состояние `disabled`.
///
/// Правило макета зашито в варианты: охряная заливка есть только у `.primary`,
/// и на экране такая кнопка должна быть одна.
struct TGButton: View {
    enum Variant: String, CaseIterable, Sendable {
        case primary
        case secondary
        case quiet
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

    let title: String
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
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .labelStyle(TGButtonLabelStyle(hasIcon: systemImage != nil))
            .font(size.style.font)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
            .padding(.horizontal, fullWidth ? 0 : Token.Space.s20)
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
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: Token.Duration.instant), value: configuration.isPressed)
    }

    private var background: Color {
        guard isEnabled else { return Token.Component.Button.Disabled.background }
        switch variant {
        case .primary: return Token.Component.Button.Primary.background
        case .secondary: return Token.Component.Button.Secondary.background
        case .quiet: return .clear
        case .destructive: return Token.Component.Button.Destructive.background
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Token.Component.Button.Disabled.label }
        switch variant {
        case .primary: return Token.Component.Button.Primary.label
        case .secondary: return Token.Component.Button.Secondary.label
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
    let unit: String
    var step: Int = 1
    var range: ClosedRange<Int> = 0...999

    var body: some View {
        HStack(spacing: Token.Space.s20) {
            TGStepButton(symbol: "minus") { adjust(-step) }
            VStack(spacing: 0) {
                Text("\(value)").textStyle(AppFont.hero)
                Text(unit).textStyle(AppFont.caption)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(value) \(unit)")
            TGStepButton(symbol: "plus") { adjust(step) }
        }
        .frame(maxWidth: .infinity)
    }

    private func adjust(_ delta: Int) {
        value = min(range.upperBound, max(range.lowerBound, value + delta))
        Haptics.tap()
    }
}
