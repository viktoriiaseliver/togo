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
    /// Название экрана в шапке-плакате. Rounded и на цветной подложке.
    ///
    /// Кегль 40 — тот, что назвало решение дизайна. Первая редакция
    /// стояла на `screen: 34`, потому что сорока в токенах не было
    /// вовсе; токен `FontSize.poster` завели в ответ на эту запись,
    /// и строка переехала на него.
    ///
    /// **Не перепутать с `Radius.poster = 44`.** Имя одно, величины
    /// разные, и обе про плакат: одна кегль, другая скругление.
    static let posterHeaderTitle = TextStyleToken(size: Token.FontSize.poster,
                                                  weight: Token.FontWeight.bold,
                                                  color: Token.Poster.labelOnColor,
                                                  rounded: true,
                                                  relativeTo: .largeTitle)

    /// Подзаголовок шапки-плаката. `captionOnColor`, а не `caption`:
    /// у плаката три семьи текста, и `caption` честен только
    /// на нейтральном блоке — на синем в светлой он даёт 1,10.
    static let posterHeaderSubtitle = TextStyleToken(size: Token.FontSize.meta,
                                                     weight: Token.FontWeight.regular,
                                                     color: Token.Poster.captionOnColor,
                                                     relativeTo: .subheadline)

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
    /// в системе не существует.
    ///
    /// **Берёт `FontSize.micro`, а не `meta`, с 15.10.2026 — и вот
    /// почему это правка, а не косметика.** До сегодня стиль с именем
    /// `micro` брал `meta` = 15, то есть **ступень `FontSize.micro` = 14
    /// не читал в приложении никто**: замер 15.10, живых читателей ноль.
    /// Прежний доккомментарий это называл («мета сведена к пятнадцати»),
    /// и решение было осознанным — но у него была цена, которой никто
    /// не мерил.
    ///
    /// Цена: ступень **уезжает дизайнеру** и в `tokens.css`
    /// (`--primitive-font-size-micro: 14px`), и в Фигму
    /// (`font/size/micro`). Значит дизайнер, применивший `font/size/micro`,
    /// получал **14 в макете и 15 в приложении** — одно имя, два значения,
    /// по разные стороны границы. Доккомментарий Swift в Фигму
    /// не уезжает, а ступень уезжает.
    ///
    /// > **Источник правды может содержать решение, которого не исполняет
    /// > ни один читатель.** Грепом это не видно: имя находится, значение
    /// > находится, а вызова по имени нет. Опусти `FontSize.micro` назад
    /// > до 12 — на экране не изменилось бы ничего, и ни один тест
    /// > не покраснел бы.
    ///
    /// Решение Виктории 15.10.2026, прямым вопросом: **«Пол 14, макет
    /// поправить»** — то есть правило остаётся, а исполняемым его делает
    /// эта строка. Радиус: **50 вызовов `AppFont.micro` в 34 файлах**
    /// (замер 15.10; час назад было 49 — число живое, считать грепом,
    /// а не отсюда). Приёмка — **кадр**, не прогон: правка меняет то,
    /// что человек читает.
    ///
    /// Ось привязки Dynamic Type оставлена `.footnote` нарочно: менялся
    /// кегль, а не роль, и трогать обе вещи одной правкой значит потерять
    /// причину красного.
    static let micro = TextStyleToken(size: Token.FontSize.micro, weight: Token.FontWeight.regular, color: Token.Ink.secondary,
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
