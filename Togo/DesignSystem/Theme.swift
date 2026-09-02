import SwiftUI

/// Тема — то, что дочерние компоненты наследуют от родителя, не спрашивая.
///
/// Зачем: в Figma компонент берёт цвет поверхности от фрейма, в который вложен.
/// Здесь то же самое — карточка кладёт в окружение свою поверхность, и любой
/// вложенный компонент рисуется правильно, даже если его вынесли из другого экрана.
struct Theme: Equatable, Sendable {
    var surface: Surface
    var density: Density

    /// На какой поверхности мы сейчас стоим. Дочерние компоненты выбирают
    /// по ней свой фон и разделители.
    enum Surface: Equatable, Sendable {
        case screen
        case card
        case sunken
        case accent

        var background: Color {
            switch self {
            case .screen: Token.Surface.screen
            case .card: Token.Surface.card
            case .sunken: Token.Surface.sunken
            case .accent: Token.Action.primaryQuiet
            }
        }

        /// Поверхность, которую положит внутрь себя вложенный контейнер.
        var nested: Surface {
            switch self {
            case .screen: .card
            case .card, .accent: .sunken
            case .sunken: .card
            }
        }

        var separator: Color { Token.Surface.hairline }
    }

    /// Плотность влияет на отступы и высоту строк. Экран задаёт её один раз,
    /// компоненты наследуют.
    enum Density: Equatable, Sendable {
        case comfortable
        case compact

        var rowPadding: CGFloat { self == .comfortable ? Token.Space.s12 : Token.Space.s8 }
        var cardPadding: CGFloat { self == .comfortable ? Token.Component.Card.padding : Token.Space.s12 }
        var stack: CGFloat { self == .comfortable ? Token.Spacing.stack : Token.Space.s10 }
    }

    static let `default` = Theme(surface: .screen, density: .comfortable)
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Передать детям другую поверхность. Ровно один аргумент — так же,
    /// как свойство компонента в Figma.
    func themeSurface(_ surface: Theme.Surface) -> some View {
        transformEnvironment(\.theme) { $0.surface = surface }
    }
}
