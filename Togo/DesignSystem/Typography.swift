import SwiftUI

/// Текстовые стили. Один стиль — одна строка токенов, как текстовый стиль
/// в Figma: кегль, начертание, цвет по умолчанию.
///
/// Шрифтов два, и роли у них разные.
///
/// **SF Pro** — весь интерфейс: заголовки, строки, меты. Он уже загружен,
/// умеет Dynamic Type из коробки и не тянет за собой лицензию.
///
/// **Onest ExtraBold** — только вордмарк и крупные числа от 28 пунктов:
/// секундомер прогулки, обратный отсчёт натощак, вес. Это те цифры,
/// на которые смотрят с расстояния вытянутой руки, и им нужен характер,
/// которого у системного шрифта нет. Больше нигде он не появляется —
/// иначе перестал бы быть брендом и стал просто ещё одним шрифтом.
struct TextStyleToken: Equatable, Sendable {
    /// Имя из таблицы шрифта, а не имя файла: iOS ищет именно его.
    static let brandFont = "Onest-ExtraBold"

    var size: CGFloat
    var weight: Font.Weight
    var color: Color
    var rounded: Bool = false
    var monospacedDigits: Bool = false
    /// Брендовый шрифт вместо системного.
    var brand: Bool = false

    var font: Font {
        if brand {
            // `relativeTo` обязателен: без него кастомный шрифт
            // перестаёт слушаться Dynamic Type, и человек с крупным
            // текстом получает мелкие цифры именно там, где они важнее
            // всего.
            return .custom(Self.brandFont, size: size, relativeTo: .largeTitle)
        }
        var font = Font.system(size: size, weight: weight, design: rounded ? .rounded : .default)
        if monospacedDigits { font = font.monospacedDigit() }
        return font
    }

    func color(_ color: Color) -> TextStyleToken {
        var copy = self
        copy.color = color
        return copy
    }

    func weight(_ weight: Font.Weight) -> TextStyleToken {
        var copy = self
        copy.weight = weight
        return copy
    }
}

enum AppFont {
    static let screenTitle = TextStyleToken(size: Token.FontSize.screen, weight: Token.FontWeight.bold, color: Token.Ink.primary)
    static let sectionTitle = TextStyleToken(size: Token.FontSize.section, weight: Token.FontWeight.semibold, color: Token.Ink.primary)
    static let cardTitle = TextStyleToken(size: Token.FontSize.title, weight: Token.FontWeight.semibold, color: Token.Ink.primary)
    static let body = TextStyleToken(size: Token.FontSize.body, weight: Token.FontWeight.regular, color: Token.Ink.primary)
    static let bodyEmphasis = TextStyleToken(size: Token.FontSize.body, weight: Token.FontWeight.medium, color: Token.Ink.primary)
    static let caption = TextStyleToken(size: Token.FontSize.caption, weight: Token.FontWeight.regular, color: Token.Ink.secondary)
    static let captionEmphasis = TextStyleToken(size: Token.FontSize.caption, weight: Token.FontWeight.medium, color: Token.Ink.primary)
    /// Слабый серый допустим только с 14pt и крупнее — ниже не хватает контраста,
    /// поэтому micro всегда medium и никогда не faint по умолчанию.
    static let micro = TextStyleToken(size: Token.FontSize.micro, weight: Token.FontWeight.medium, color: Token.Ink.secondary)

    /// Крупные числа: секундомер, задержка маркера, вес.
    static func numeric(_ size: CGFloat, weight: Font.Weight = Token.FontWeight.semibold) -> TextStyleToken {
        TextStyleToken(size: size, weight: weight, color: Token.Ink.primary, rounded: true, monospacedDigits: true)
    }

    /// Крупные числа бренда: секундомер, отсчёт натощак, вес.
    static let display = TextStyleToken(size: Token.FontSize.display, weight: Token.FontWeight.bold,
                                        color: Token.Ink.primary, monospacedDigits: true, brand: true)
    static let hero = TextStyleToken(size: Token.FontSize.hero, weight: Token.FontWeight.bold,
                                     color: Token.Ink.primary, monospacedDigits: true, brand: true)
    /// Вордмарк: онбординг, «о приложении».
    static let wordmark = TextStyleToken(size: Token.FontSize.display, weight: Token.FontWeight.bold,
                                         color: Token.Ink.primary, brand: true)
}

extension View {
    /// Один модификатор вместо пары .font + .foregroundStyle:
    /// стиль всегда приезжает целиком, как из Figma.
    func textStyle(_ style: TextStyleToken) -> some View {
        self.font(style.font).foregroundStyle(style.color)
    }
}

extension Text {
    func textStyle(_ style: TextStyleToken) -> Text {
        self.font(style.font).foregroundColor(style.color)
    }
}
