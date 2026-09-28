import SwiftUI
import UIKit

/// Figma: `Chip`. Свойства — `label`, `sublabel`, `selected`, `tone`.
struct TGChip: View {
    /// Надпись хранится готовым `Text`, потому что приходит двумя путями.
    ///
    /// Литерал в коде — ключ каталога и переводится. А `TGChipGroup`
    /// зовёт замыкание, которое отдаёт уже собранную строку: из
    /// перечисления (там перевод берёт `String(localized:)`) или прямо
    /// из данных — кличка, марка корма. Второе переводить нельзя,
    /// поэтому для него отдельный вход, `verbatim:`.
    private let заголовок: Text
    private let подзаголовок: Text?
    var isSelected: Bool = false
    var tone: TGTone = .neutral
    let action: () -> Void

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
         isSelected: Bool = false, tone: TGTone = .neutral,
         action: @escaping () -> Void) {
        self.заголовок = Text(title)
        self.подзаголовок = subtitle.map { Text($0) }
        self.isSelected = isSelected
        self.tone = tone
        self.action = action
    }

    init(verbatim title: String, subtitle: String? = nil,
         isSelected: Bool = false, tone: TGTone = .neutral,
         action: @escaping () -> Void) {
        self.заголовок = Text(verbatim: title)
        self.подзаголовок = subtitle.map { Text(verbatim: $0) }
        self.isSelected = isSelected
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            TGTile(isSelected: isSelected, tone: tone, minHeight: Token.Component.Chip.height) {
                VStack(spacing: Token.Space.s2) {
                    заголовок
                        .textStyle(AppFont.captionEmphasis.color(foreground))
                        .multilineTextAlignment(.center)
                        .wraps()
                    if let подзаголовок {
                        подзаголовок
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

    /// Колонка растёт вместе с кеглем.
    ///
    /// При прибитых ста двадцати точках на крупной системной настройке
    /// чипы ломались посреди слова — кадр 28.09 на экране прав:
    /// «Владеле / ц», «Ухажива / ющий», «Помощн / ик», «приглаш / ения».
    /// Роль, разорванная пополам, не читается как роль.
    ///
    /// Масштабируем ШИРИНУ, а не ужимаем текст: на доступных размерах
    /// сетка сама сойдётся к одной колонке, и это правильный исход —
    /// два разорванных слова хуже одного целого столбца.
    private var scaledMinimumWidth: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: minimumWidth)
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: scaledMinimumWidth), spacing: Token.Space.s8)],
            alignment: .leading,
            spacing: Token.Space.s8
        ) {
            ForEach(items, id: \.self) { item in
                TGChip(
                    // Строка приезжает из замыкания уже собранной —
                    // перечислением или данными, и переводить её второй раз
                    // нельзя.
                    verbatim: title(item),
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
