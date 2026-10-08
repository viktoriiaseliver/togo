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

    /// Настоящая высота закреплённого низа, измеренная на отрисовке.
    ///
    /// **Здесь стояло число 120, и оно было меньше факта.** Панель
    /// занимает сумму высот своих блоков плюс отступы, и у слота
    /// с двумя кнопками это 126:
    ///
    /// ```
    /// OnboardingSteps:301  кнопка .large 60 + .medium 50 + отступы  126   −6 ✗
    /// OnboardingSteps:346  то же                                     126   −6 ✗
    /// OnboardingSteps:130  кнопка + Button(minHeight: 44)            120    0 ⚠
    /// остальные десять слотов                                            +26…+62
    /// ```
    ///
    /// Шесть точек — это не косметика, и различитель здесь не размер,
    /// а **достижимость**: у десяти слотов последний блок выходит
    /// из-под панели, если прокрутить до упора, а у `:301` и `:346`
    /// последние шесть точек **не выходят никогда**. У `:130` запас
    /// ровно ноль — то есть «значение вычислено, а не увидено».
    ///
    /// Что от этого не прочитывалось: на `:301` — шаг ПРИГЛАШЕНИЯ
    /// («за безопасность собаки денег не берём»), на `:346` — строка
    /// про одно напоминание вместо восьми, на `:130` — объяснение,
    /// что «Здоровье» можно включить потом. Это онбординг, то есть
    /// первое, что увидит приглашённый.
    ///
    /// **Починка по форме, а не по трём адресам.** Другая константа,
    /// побольше, закрыла бы сегодняшние три слота и вернула бы дефект
    /// на первом крупном кегле: при увеличенном Dynamic Type подпись
    /// растёт, кнопка идёт выше `minHeight`, и в минус уходят слоты
    /// с запасом +26, возможно и +52. Выведенная высота закрывает это
    /// сама.
    ///
    /// > **Пока одно место решает высоту панели, а другое — запас
    /// > под неё, они разойдутся, и разойдутся молча.** Тот же
    /// > принцип, которым заливка и подпись сведены в `MarkFill`.
    ///
    /// Чего правка НЕ делает: подложки у низа по-прежнему нет.
    /// У соседнего `TGSheet.footerBar` она есть (`.regularMaterial`),
    /// и какой из двух каркасов прав — **решение дизайна**, не моё:
    /// добавить фон значит изменить вид всех тринадцати слотов. Здесь
    /// константа была просто меньше факта, и это починка, а не выбор.
    @State private var высотаНиза: CGFloat = 0

    /// Запас под панелью: её настоящая высота плюс тот же воздух,
    /// что у экрана без панели. Ноль до первой отрисовки — один кадр
    /// экран живёт с запасом `s24`, как будто панели нет, и это видно
    /// только прокруткой в первые миллисекунды.
    private var запасПодНизом: CGFloat {
        Bottom.self == EmptyView.self ? Token.Space.s24 : высотаНиза + Token.Space.s24
    }

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
                .padding(.bottom, запасПодНизом)
            }
            if Bottom.self != EmptyView.self {
                VStack(spacing: Token.Space.s8) { bottom }
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .padding(.bottom, Token.Space.s8)
                    // **Это ЗАМЕР, а не подложка.** `Color.clear`
                    // не рисует ничего: вид панели не меняется ни
                    // на точку, и решение про `.regularMaterial`
                    // остаётся за дизайном. Единственное назначение
                    // слоя — отдать высоту тому, кто считает запас.
                    //
                    // `onAppear` плюс `onChange`, а не `PreferenceKey`:
                    // цель сборки — iOS 17, где `onGeometryChange`
                    // ещё нет, а `onPreferenceChange` в Swift 6 требует
                    // `@Sendable`-замыкание и спорит с `@State`.
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { высотаНиза = geo.size.height }
                                .onChange(of: geo.size.height) { _, новая in
                                    высотаНиза = новая
                                }
                        }
                    }
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
