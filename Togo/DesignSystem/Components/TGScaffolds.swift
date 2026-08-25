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
struct TGSheet<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
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
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(title).textStyle(AppFont.screenTitle)
            if let subtitle {
                Text(subtitle).textStyle(AppFont.caption)
            }
        }
        .padding(.top, Token.Space.s8)
        .accessibilityAddTraits(.isHeader)
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
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, content: content, footer: { EmptyView() })
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
