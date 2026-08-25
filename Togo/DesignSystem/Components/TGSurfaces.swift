import SwiftUI

// MARK: - Divider

/// Figma: `Divider`. Хайрлайн 1px. Бордеров у карточек нет — разделяет только это.
struct TGDivider: View {
    @Environment(\.theme) private var theme
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(theme.surface.separator)
            .frame(height: Token.Size.hairline)
            .padding(.leading, inset)
    }
}

// MARK: - Card

/// Figma: `Card`. Родительский контейнер: кладёт детям свою поверхность
/// в окружение, поэтому вложенные компоненты не спрашивают, где они стоят.
///
/// Свойства компонента: `padding`, `surface`, `elevated`.
struct TGCard<Content: View>: View {
    @Environment(\.theme) private var theme

    var surface: Theme.Surface = .card
    var padding: CGFloat?
    var elevated: Bool = true
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing ?? Token.Space.s12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding ?? theme.density.cardPadding)
        .background(surface.background, in: shape)
        .shadow(color: elevated ? Token.Elevation.card.color : .clear,
                radius: Token.Elevation.card.radius,
                x: Token.Elevation.card.x,
                y: Token.Elevation.card.y)
        .themeSurface(surface)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Token.Component.Card.radius, style: .continuous)
    }
}

/// Figma: `Tile`. Утопленная плитка без тени — поля ввода, плитки выбора.
struct TGTile<Content: View>: View {
    var isSelected: Bool = false
    var tone: TGTone = .neutral
    var minHeight: CGFloat = Token.Size.tapTarget
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(background, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            .themeSurface(isSelected ? .accent : .sunken)
    }

    private var background: Color {
        guard isSelected else { return Token.Surface.sunken }
        return tone == .alarm ? Token.Status.overdueBg : Token.Action.primaryQuiet
    }
}

/// Общая ось «настроения» для всех компонентов. В Figma — одно свойство `tone`
/// на кнопке, чипе и плашке, а не три разных перечисления.
nonisolated enum TGTone: String, CaseIterable, Sendable {
    case neutral
    case done
    case waiting
    case alarm

    var background: Color {
        switch self {
        case .neutral: Token.Surface.sunken
        case .done: Token.Status.doneBg
        case .waiting: Token.Status.waitingBg
        case .alarm: Token.Status.overdueBg
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: Token.Ink.primary
        case .done: Token.Status.doneText
        case .waiting: Token.Status.waitingText
        case .alarm: Token.Status.overdueText
        }
    }
}
