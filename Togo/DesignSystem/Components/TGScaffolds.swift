import SwiftUI

/// Figma: `SheetHandle`. Ручка 36×4 — одинаковая во всех шторках.
struct TGSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Token.Component.Sheet.handleColor)
            .frame(width: Token.Component.Sheet.handleWidth, height: Token.Component.Sheet.handleHeight)
            .padding(.top, Token.Space.s8)
            .padding(.bottom, Token.Space.s4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// Figma: `Sheet`. Родительский каркас шторки: ручка, заголовок, прокрутка,
/// действие внизу. Дети приходят слотом — так же, как слот в Figma-компоненте.
///
/// Выход есть всегда: ручка, свайп вниз и явный крестик. Эвристика Нильсена
/// №3 — свобода и контроль: из любого места должен быть виден путь назад,
/// а не только жест, о котором надо догадаться.
struct TGSheet<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var subtitle: String?
    /// Подпись кнопки закрытия. Меняется там, где «Закрыть» звучит неверно —
    /// например «Отмена» в форме, которая что-то создаёт.
    var closeTitle: String = "Закрыть"
    /// Что делать при закрытии, если недостаточно просто убрать шторку.
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            TGSheetHandle()
            ScrollView {
                VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                    header
                    content
                }
                .padding(.horizontal, Token.Spacing.screenPadding)
                .padding(.bottom, Token.Space.s28)
            }
            .scrollBounceBehavior(.basedOnSize)
            footerBar
        }
        .background(Token.Component.Sheet.background)
        .themeSurface(.screen)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            VStack(alignment: .leading, spacing: Token.Space.s4) {
                Text(title).textStyle(AppFont.screenTitle)
                if let subtitle {
                    Text(subtitle).textStyle(AppFont.caption)
                }
            }
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                onClose?()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Token.Ink.secondary)
                    .frame(width: 30, height: 30)
                    .background(Token.Surface.sunken, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeTitle)
        }
        .padding(.top, Token.Space.s8)
    }

    @ViewBuilder
    private var footerBar: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: Token.Space.s8) { footer }
                .padding(.horizontal, Token.Spacing.screenPadding)
                .padding(.top, Token.Space.s10)
                .padding(.bottom, Token.Space.s8)
                .background(.regularMaterial)
        }
    }
}

extension TGSheet where Footer == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        closeTitle: String = "Закрыть",
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, closeTitle: closeTitle,
                  onClose: onClose, content: content, footer: { EmptyView() })
    }
}

/// Figma: `Screen`. Тёплая бумага, единые отступы, слот под нижнюю панель.
struct TGScreen<Content: View, Bottom: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        ZStack(alignment: .bottom) {
            Token.Surface.screen.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                    if let title {
                        Text(title)
                            .textStyle(AppFont.screenTitle)
                            .padding(.top, Token.Space.s4)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .padding(.horizontal, Token.Spacing.screenPadding)
                .padding(.bottom, Bottom.self == EmptyView.self ? Token.Space.s24 : 120)
            }
            if Bottom.self != EmptyView.self {
                VStack(spacing: Token.Space.s8) { bottom }
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .padding(.bottom, Token.Space.s8)
            }
        }
        .themeSurface(.screen)
    }
}

extension TGScreen where Bottom == EmptyView {
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, bottom: { EmptyView() })
    }
}
