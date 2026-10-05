import SwiftUI
import UIKit

/// Текстовые стили. Один стиль — одна строка токенов, как текстовый стиль
/// в Figma: кегль, начертание, цвет по умолчанию.
///
/// Шрифт системный, и только он. Брендовый Onest в приложении был
/// ровно один ход дизайна и убран вместе с ним: новая шкала собрана
/// на SF Pro целиком, а вложенный шрифт, которым никто не пользуется, —
/// это лишние сто килобайт и лишняя строка в лицензиях.
struct TextStyleToken: Equatable, Sendable {
    var size: CGFloat
    var weight: Font.Weight
    var color: Color
    var rounded: Bool = false
    var monospacedDigits: Bool = false
    /// К какой системной ступени привязан кегль при масштабировании.
    ///
    /// Нужна не для красоты: `UIFontMetrics` растит разные ступени
    /// по-разному. Заголовок на крупной настройке прибавляет меньше,
    /// чем подпись, — иначе шапка выдавила бы всё остальное за экран.
    var relativeTo: UIFont.TextStyle = .body

    /// Кегль, **умноженный на настройку размера текста в iOS**.
    ///
    /// **До 28.09 здесь стоял голый `Font.system(size:)`, и это значило,
    /// что Dynamic Type не работал НИГДЕ в приложении.** Человек,
    /// увеличивший текст в настройках айфона, не видел разницы ни
    /// на одном экране: `Font.system(size:)` берёт точки как есть
    /// и настройку не спрашивает. Одна строка — весь продукт.
    ///
    /// Класс тот же, на котором Togo обжигался трижды: значение верное,
    /// имя на месте, а от упоминания ничего не происходит. Только здесь
    /// упоминания не было вовсе — был размер, который просто никто
    /// не масштабировал.
    ///
    /// `UIFontMetrics` читает текущую ступень в момент вычисления.
    /// Свойство вычисляется при построении тела вью, а смена настройки
    /// перестраивает тела — поэтому значение приезжает новое. Названная
    /// граница: это не подписка, а чтение в нужный момент; если когда-то
    /// шрифт понадобится вне построения тела, масштаб там будет
    /// от прошлой ступени.
    var font: Font {
        let scaled = UIFontMetrics(forTextStyle: relativeTo).scaledValue(for: size)
        var font = Font.system(size: scaled, weight: weight,
                               design: rounded ? .rounded : .default)
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
    /// Название экрана. 34/700 — как большой заголовок в iOS.
    static let screenTitle = TextStyleToken(size: Token.FontSize.screen, weight: Token.FontWeight.bold, color: Token.Ink.primary,
                                            relativeTo: .largeTitle)
    /// Заголовок группы и карточки. 20/600 — в системе это одна ступень.
    static let sectionTitle = TextStyleToken(size: Token.FontSize.section, weight: Token.FontWeight.semibold, color: Token.Ink.primary,
                                             relativeTo: .title3)
    static let cardTitle = TextStyleToken(size: Token.FontSize.section, weight: Token.FontWeight.semibold, color: Token.Ink.primary,
                                          relativeTo: .title3)
    /// Тело списка. 17/400.
    static let body = TextStyleToken(size: Token.FontSize.body, weight: Token.FontWeight.regular, color: Token.Ink.primary)
    static let bodyEmphasis = TextStyleToken(size: Token.FontSize.body, weight: Token.FontWeight.medium, color: Token.Ink.primary)
    /// Мета: время, автор, подпись. 15/400.
    static let caption = TextStyleToken(size: Token.FontSize.meta, weight: Token.FontWeight.regular, color: Token.Ink.secondary,
                                        relativeTo: .subheadline)
    static let captionEmphasis = TextStyleToken(size: Token.FontSize.meta, weight: Token.FontWeight.medium, color: Token.Ink.primary,
                                                relativeTo: .subheadline)
    /// Раньше здесь было двенадцать пунктов. Ниже четырнадцати
    /// в системе не существует, и мета сведена к пятнадцати.
    static let micro = TextStyleToken(size: Token.FontSize.meta, weight: Token.FontWeight.regular, color: Token.Ink.secondary,
                                      relativeTo: .footnote)
    /// Капс: название секции. 14/600, в вёрстке — прописными.
    static let caps = TextStyleToken(size: Token.FontSize.caption, weight: Token.FontWeight.semibold, color: Token.Ink.secondary,
                                     relativeTo: .caption1)

    /// Числа в строках и на плитках.
    static func numeric(_ size: CGFloat, weight: Font.Weight = Token.FontWeight.semibold) -> TextStyleToken {
        TextStyleToken(size: size, weight: weight, color: Token.Ink.primary, monospacedDigits: true,
                       relativeTo: .body)
    }

    /// Крупная цифра карточки.
    static let display = TextStyleToken(size: Token.FontSize.display, weight: Token.FontWeight.bold,
                                        color: Token.Ink.primary, monospacedDigits: true,
                                        relativeTo: .title2)
    /// Герой: ответ на главный вопрос. Один на экран.
    ///
    /// Вес `light`, а не `bold`: поколение «финал» 05.10 задаёт крупные
    /// цифры как SF Pro Rounded 300 (`--fw-number`). Прежний `bold` был
    /// весом ПРОТИВОПОЛОЖНЫМ, и это самое заметное глазом расхождение
    /// кода с макетом — заметнее смены палитры, потому что цифра
    /// на экране одна и самая большая.
    ///
    /// Размер остался 56pt, а не 96pt макета: там он задан С ОСЬЮ
    /// УСТРОЙСТВА (96 на iPhone 402, 80 на SE 375, 112 на iPad), а оси
    /// в токенах нет. Плоские 96 переполнили бы узкий экран.
    static let hero = TextStyleToken(size: Token.FontSize.hero, weight: Token.FontWeight.light,
                                     color: Token.Ink.primary, monospacedDigits: true,
                                     relativeTo: .title2)
    static let wordmark = TextStyleToken(size: Token.FontSize.display, weight: Token.FontWeight.bold,
                                         color: Token.Ink.primary)
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

    /// Тот же стиль, но цвет задаёт вызывающий.
    ///
    /// Нужно там, где цвет текста определяет **заливка под ним**, а не
    /// роль текста. `TextStyleToken` несёт свой `color`, и он красит сам
    /// `Text` — то есть побеждает `.foregroundStyle` предка. Из-за этого
    /// подпись главной кнопки оставалась светлой на светлой заливке:
    /// внешний цвет был выставлен верно и молча перекрывался.
    ///
    /// Цвет подставляется ВМЕСТО стилевого, а не поверх него — иначе
    /// порядок модификаторов снова решал бы исход.
    func textStyle(_ style: TextStyleToken, color: Color) -> Text {
        self.font(style.font).foregroundColor(color)
    }
}
