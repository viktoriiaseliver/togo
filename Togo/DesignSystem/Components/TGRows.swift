import SwiftUI

/// Figma: `SectionHeader`. Заглавная микро-строка над группой.
struct TGSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(title)
                .textStyle(AppFont.caps)
                .textCase(.uppercase)
                .kerning(0.6)
                .wraps()
            if let subtitle {
                Text(subtitle)
                    .textStyle(AppFont.caption)
                    .wraps()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Figma: `Explainer`. Объяснение стоит там, где возникает вопрос —
/// отдельной справки в приложении нет и не нужно.
struct TGExplainer: View {
    let text: String

    var body: some View {
        Text(text)
            .textStyle(AppFont.caption)
            .wraps()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figma: `ListRow`. Свойства — `title`, `value`, `systemImage`, `accessory`, `tone`.
struct TGListRow: View {
    enum Accessory: Sendable { case chevron, checkmark, none }

    @Environment(\.theme) private var theme

    let title: String
    var value: String?
    var systemImage: String?
    var accessory: Accessory = .chevron
    var tone: Color = Token.Ink.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Token.Size.iconMd, weight: .medium))
                    .foregroundStyle(Token.Ink.secondary)
                    .frame(width: Token.Space.s24)
                    .accessibilityHidden(true)
            }

            // При крупном шрифте подпись и значение перестают помещаться
            // в строку — тогда они встают друг под друга, а не ужимаются
            // до нечитаемого.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                    titleText
                    Spacer(minLength: Token.Space.s8)
                    valueText
                }
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    titleText
                    valueText
                }
            }

            accessoryView
        }
        .frame(minHeight: Token.Size.tapTarget)
        .padding(.vertical, max(0, theme.density.rowPadding - Token.Space.s12))
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .textStyle(AppFont.body.color(tone))
            .wraps()
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .textStyle(AppFont.caption)
                .wraps()
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        // Шеврон и галочка ничего не добавляют голосом: состояние строки
        // читается из её текста.
        switch accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .foregroundStyle(Token.Ink.secondary)
                .accessibilityHidden(true)
        case .checkmark:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Token.Size.iconMd, weight: .semibold))
                .foregroundStyle(Token.Action.doneText)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }
}

/// Figma: `Stat`. Число и подпись. Счётчики не украшены иконками и не раскрашены.
struct TGStat: View {
    let value: String
    let caption: String
    var size: CGFloat = 22

    var body: some View {
        VStack(spacing: Token.Space.s2) {
            Text(value)
                .textStyle(AppFont.numeric(size))
                .lineLimit(1)
                // Число лучше показать чуть мельче, чем обрезать: «190 мл»
                // с многоточием не читается вообще.
                .minimumScaleFactor(0.6)
            Text(caption)
                .textStyle(AppFont.micro)
                .multilineTextAlignment(.center)
                .wraps()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Figma: `Avatar`. Свойства — `initial`, `image`, `size`, `tint`.
struct TGAvatar: View {
    var initial: String
    var image: Data?
    var size: CGFloat = Token.Size.avatarSm
    var tint: Color = Token.Action.done

    var body: some View {
        Group {
            if let image, let uiImage = UIImage(data: image) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Подпись на аватаре.
    ///
    /// Раньше цвет выбирался сравнением тинта с двумя конкретными
    /// токенами: поменяешь тинт — и подпись молча станет нечитаемой.
    /// В тёмном наборе все аватарные фоны тёмные, поэтому подпись
    /// всегда основным цветом текста.
    private var foreground: Color { Token.Ink.primary }
}

/// Figma: `Author`. Кто записал.
///
/// Раньше здесь была ещё и зелёная галочка «синхронизировано» — у каждой
/// записи, всегда. Обмен между устройствами с тех пор появился, но
/// доставку **конкретной строки** он не отслеживает: `isSynced` по-прежнему
/// всегда `true`. То есть галочка так и осталась бы украшением,
/// притворяющимся сведениями, — вернётся, когда будет что показывать.
///
/// Инициал автора остаётся, но только когда в семье больше одного
/// человека: одному себе представляться незачем.
struct TGAuthorMark: View {
    let author: String

    var body: some View {
        Text(String(author.prefix(1)))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Token.Ink.secondary)
            .accessibilityLabel("Записала \(author)")
    }
}
