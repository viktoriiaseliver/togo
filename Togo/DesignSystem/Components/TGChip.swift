import SwiftUI

/// Figma: `Chip`. Свойства — `label`, `sublabel`, `selected`, `tone`.
struct TGChip: View {
    let title: String
    var subtitle: String?
    var isSelected: Bool = false
    var tone: TGTone = .neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TGTile(isSelected: isSelected, tone: tone, minHeight: Token.Component.Chip.height) {
                VStack(spacing: Token.Space.s2) {
                    Text(title)
                        .textStyle(AppFont.captionEmphasis.color(foreground))
                        .multilineTextAlignment(.center)
                        .wraps()
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(AppFont.micro.color(Token.Ink.secondary))
                            .multilineTextAlignment(.center)
                            .wraps()
                    }
                }
                .padding(.horizontal, Token.Space.s14)
                .padding(.vertical, Token.Space.s8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        isSelected && tone == .alarm ? Token.Status.overdueText : Token.Ink.primary
    }
}

/// Figma: `ChipGroup`. Родитель, который раскладывает чипы с переносом.
/// Дети — экземпляры `Chip`; выбор наружу отдаётся замыканием.
struct TGChipGroup<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var subtitle: (Item) -> String? = { _ in nil }
    var isSelected: (Item) -> Bool
    var tone: (Item) -> TGTone = { _ in .neutral }
    var minimumWidth: CGFloat = 120
    let onTap: (Item) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: Token.Space.s8)],
            alignment: .leading,
            spacing: Token.Space.s8
        ) {
            ForEach(items, id: \.self) { item in
                TGChip(
                    title: title(item),
                    subtitle: subtitle(item),
                    isSelected: isSelected(item),
                    tone: tone(item)
                ) {
                    onTap(item)
                }
            }
        }
    }
}
