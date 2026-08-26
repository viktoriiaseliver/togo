import SwiftUI

/// Figma: `Loading`. Состояние ожидания.
///
/// Молчащий экран во время работы читается как сломанный. Спиннер без слов
/// читается почти так же: непонятно, чего ждать и сколько. Поэтому здесь
/// всегда есть строка, которая говорит, что именно происходит.
struct TGLoading: View {
    let message: String
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            ProgressView()
                .tint(Token.Ink.secondary)
            Text(message)
                .textStyle(AppFont.caption)
                .wraps()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isCompact ? Token.Size.tapTarget : 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// Пустое состояние одного вида на всё приложение: что это, почему пусто
/// и что нажать. «Нет данных» без объяснения — это тупик.
struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        TGCard {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Token.Ink.silhouette)
                .accessibilityHidden(true)
            Text(title).textStyle(AppFont.cardTitle)
            Text(message).textStyle(AppFont.caption)
            if let actionTitle, let action {
                TGButton(title: actionTitle, variant: .secondary, size: .medium, action: action)
            }
        }
    }
}

/// Три состояния одного экрана: ждём, пусто, есть что показать.
///
/// Вынесено в один компонент, потому что раньше каждый экран решал это
/// по-своему, и «загружается» не было вообще ни на одном.
struct TGStateful<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    var loadingMessage: String
    var emptyImage: String
    var emptyTitle: String
    var emptyMessage: String
    var emptyActionTitle: String?
    var emptyAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        if isLoading {
            TGCard { TGLoading(message: loadingMessage) }
                .transition(.opacity)
        } else if isEmpty {
            EmptyStateCard(
                systemImage: emptyImage,
                title: emptyTitle,
                message: emptyMessage,
                actionTitle: emptyActionTitle,
                action: emptyAction
            )
            .transition(.opacity)
        } else {
            content
        }
    }
}
