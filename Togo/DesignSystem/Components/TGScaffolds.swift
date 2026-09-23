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

    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// Подпись кнопки закрытия. Меняется там, где «Закрыть» звучит неверно —
    /// например «Отмена» в форме, которая что-то создаёт.
    var closeTitle: LocalizedStringKey = "Закрыть"
    /// Что делать при закрытии, если недостаточно просто убрать шторку.
    var onClose: (() -> Void)?
    /// Есть ли несохранённые правки.
    ///
    /// Пока форма пустая, шторка закрывается свайпом как обычно. Как только
    /// человек что-то ввёл, свайп перестаёт закрывать, а крестик спрашивает.
    /// Правило Apple: если действие теряет введённое, его подтверждают —
    /// смахнуть шторку вниз слишком легко случайно, а форму потом набирать
    /// заново.
    var hasUnsavedChanges: Bool = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var isConfirmingDiscard = false

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
        .interactiveDismissDisabled(hasUnsavedChanges)
        .confirmationDialog("Закрыть без сохранения?", isPresented: $isConfirmingDiscard,
                            titleVisibility: .visible) {
            Button("Не сохранять", role: .destructive) { close() }
            Button("Продолжить заполнять", role: .cancel) {}
        } message: {
            Text("Введённое не сохранится.")
        }
    }

    private func close() {
        onClose?()
        dismiss()
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

            TGCloseButton(title: closeTitle) {
                if hasUnsavedChanges { isConfirmingDiscard = true } else { close() }
            }
            // Цель 44×44 тянет заголовок вниз — компенсируем, чтобы
            // крестик остался на одной линии с первой строкой.
            .padding(.trailing, -Token.Space.s6)
            .padding(.top, -Token.Space.s6)
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
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        closeTitle: LocalizedStringKey = "Закрыть",
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, closeTitle: closeTitle,
                  onClose: onClose, content: content, footer: { EmptyView() })
    }
}

/// Figma: `Screen`. Тёплая бумага, единые отступы, слот под нижнюю панель.
struct TGScreen<Content: View, Bottom: View>: View {
    var title: LocalizedStringKey?
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
    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, bottom: { EmptyView() })
    }
}
