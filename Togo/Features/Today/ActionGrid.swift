import SwiftUI

/// Куда ведёт каждая кнопка. Одно перечисление на весь главный экран —
/// так видно, что путей ровно столько, сколько кнопок.
enum TodayRoute: Identifiable, Hashable {
    case needs
    case walk
    case walkResult
    case stool
    case meal
    case treat
    case incident
    case note
    case training
    case more
    case dayOut
    case edit(UUID)

    var id: String {
        switch self {
        case .edit(let id): "edit-\(id)"
        default: String(describing: self)
        }
    }
}

/// Кнопок в сетке всегда четыре или пять, пятая — «Ещё».
/// Главное действие одно и оно охряное.
struct ActionGrid: View {
    let portionGrams: Int
    let isTravelling: Bool
    let canWriteMedical: Bool
    var onSelect: (TodayRoute) -> Void

    /// Настройка размера текста в iOS. Читается здесь, а не угадывается
    /// по ширине экрана: ширина не меняется, когда человек увеличивает
    /// шрифт, а раскладка обязана.
    @Environment(\.dynamicTypeSize) private var размерТекста

    private var стул: some View {
        SmallAction(title: "Стул", systemImage: "leaf") { onSelect(.stool) }
    }
    private var еда: some View {
        SmallAction(title: "Еда", subtitle: portionGrams > 0 ? "\(portionGrams) г" : nil,
                    systemImage: "fork.knife") { onSelect(.meal) }
    }
    private var инцидент: some View {
        SmallAction(title: "Инцидент", systemImage: "exclamationmark.triangle") { onSelect(.incident) }
    }
    private var ещё: some View {
        SmallAction(title: "Ещё", systemImage: "ellipsis") { onSelect(.more) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BigAction(title: isTravelling ? "Остановка" : "Просится",
                          systemImage: isTravelling ? "car" : "figure.walk.departure",
                          isPrimary: true) {
                    onSelect(isTravelling ? .walk : .needs)
                }
                BigAction(title: "Гулять", systemImage: "figure.walk", isPrimary: false) {
                    onSelect(.walk)
                }
            }
            // Четыре плитки в ряд — пока подписи мельче доли ширины.
            //
            // `maxWidth: .infinity` делит поровну только до тех пор, пока
            // идеальная ширина текста в долю влезает. На крупной системной
            // настройке четыре подписи в строку не помещаются ПО УСТРОЙСТВУ,
            // и кадр 28.09 показал ровно это: «Стул» и «Ещё» вылезли
            // за свои плитки.
            //
            // Ужимать дальше некуда — это уже был бы шрифт, который человек
            // и увеличивал. Поэтому на доступных размерах ряд становится
            // сеткой два на два: места вдвое больше, порядок чтения тот же.
            if размерТекста.isAccessibilitySize {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { стул; еда }
                    HStack(spacing: 10) { инцидент; ещё }
                }
            } else {
                HStack(spacing: 10) { стул; еда; инцидент; ещё }
            }
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }
}

struct BigAction: View {
    /// Надпись — ключ каталога, а не готовая строка.
    ///
    /// `Text` со значением типа `String` рисует текст дословно, мимо
    /// каталога: 23.09 из-за этого французский кадр витрины показал
    /// «Просится» и «Гулять» по-русски при живом переводе. Литерал,
    /// приехавший через `String`, локализацию не проходит.
    let title: LocalizedStringKey
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                // Цвет подписи задаётся здесь, а не наследуется: стиль
                // несёт собственный Ink.primary и красит сам Text, то
                // есть побеждает foregroundStyle предка. Внешний цвет
                // стоял верный и молча перекрывался — подпись оставалась
                // светлой на светлой заливке.
                Text(title)
                    .textStyle(AppFont.cardTitle,
                               color: isPrimary ? Token.Component.Button.Primary.label
                                                : Token.Component.Button.Secondary.label)
                    .lineLimit(1)
                    // 0,75 хватало на обычном кегле и не хватило
                    // на крупном: главная кнопка приложения печаталась
                    // как «Просит…» — кадр 28.09. Обрезать подпись
                    // главного действия нельзя ни при какой настройке.
                    .minimumScaleFactor(0.45)
            }
            // Подпись берётся у компонентного токена, а не у Ink.primary.
            // Прежде оба варианта красились одним светлым: на тёмной
            // заливке это верно, на светлой — нет. Белый на мяте давал
            // 1,68:1, светлый на синем «Льда» — 1,98:1. Главная кнопка
            // приложения не была читаемой ни разу, и тест на токен всё
            // это время был зелёным: он проверял, что onAccent правильный,
            // а экран его не звал.
            .foregroundStyle(isPrimary ? Token.Component.Button.Primary.label
                                       : Token.Component.Button.Secondary.label)
            .padding(.horizontal, Token.Space.s8)
            .frame(maxWidth: .infinity,
                   minHeight: isPrimary ? Token.Component.Button.Primary.height
                                        : Token.Component.Button.Secondary.height)
            .background(
                RoundedRectangle(
                    cornerRadius: isPrimary ? Token.Component.Button.Primary.radius
                                            : Token.Component.Button.Secondary.radius,
                    style: .continuous
                )
                .fill(isPrimary ? Token.Component.Button.Primary.background
                                : Token.Component.Button.Secondary.background)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

struct SmallAction: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Плитка — `TGTile`, а не свой прямоугольник.
            //
            // До 05.10 здесь стоял `RoundedRectangle(Token.Radius.tile)
            // .fill(Token.Surface.sunken)` — побайтно то же, что делает
            // компонент, минус `.themeSurface(.sunken)`. Сегодня это
            // не ломало ничего: `theme.surface` читают только `TGDivider`
            // и `TGCard`, а внутри плитки их нет. **Чинится не дефект,
            // а условие его появления:** положи сюда разделитель — он
            // возьмёт цвет от родительской поверхности, и молча.
            //
            // Двадцатью строками выше, у главной кнопки, лежит след
            // того же класса: кнопка давала 1,68:1 и не читалась ни разу
            // при зелёном тесте — тест проверял, что токен `onAccent`
            // верен, а экран его не звал, потому что собрал кнопку сам.
            TGTile(minHeight: Token.Size.tapTarget + 8) {
                VStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .accessibilityHidden(true)
                    // По токену, а не голым `Font.system(size:)`: голый
                    // размер настройку iOS не спрашивает, и 28.09 на кадре
                    // при крупном шрифте эти подписи остались мелкими,
                    // пока весь экран вырос. Половина экрана масштабируется,
                    // половина нет — хуже, чем если бы не масштабировался
                    // никто: выглядит поломкой, а не ограничением.
                    Text(title)
                        .textStyle(AppFont.micro, color: Token.Ink.primary)
                        .lineLimit(1)
                        // Пять плиток в ряд — колонка узкая. Чуть мельче лучше,
                        // чем «Инциде…». На крупной настройке запас глубже.
                        .minimumScaleFactor(0.5)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(AppFont.micro, color: Token.Ink.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .foregroundStyle(Token.Ink.primary)
            }
        }
        .buttonStyle(.plain)
        // Подпись под кнопкой — часть оформления, а не имени: голосом
        // и в тестах кнопка называется ровно так, как её зовут люди.
        .accessibilityLabel(Text(title))
        .accessibilityValue(subtitle.map { Text($0) } ?? Text(""))
    }
}

