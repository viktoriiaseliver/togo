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

    /// Рисовать ли линию над панелью. Разбор — у `нижняяПанель`.
    ///
    /// **По умолчанию НЕТ, и это слово дизайна, а не осторожность:**
    /// «Разделитель `line.separator` — ТОЛЬКО когда под ним есть
    /// текст». Значит у панели с одной кнопкой линии нет, и умолчание
    /// обязано быть отсутствием — иначе решение исполнится наоборот
    /// у всех девяти слотов разом.
    var разделитель: Bool = false

    var body: some View {
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
            .padding(.bottom, Token.Space.s24)
        }
        .background(Token.Surface.screen.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { нижняяПанель }
        .themeSurface(.screen)
    }

    /// Нижняя панель: СВОЁ МЕСТО, а не наложение поверх текста.
    ///
    /// # Чего стоило наложение
    ///
    /// Панель лежала в `ZStack` **без подложки**, то есть поверх
    /// прокручиваемого текста, и запас под неё считался руками:
    /// `GeometryReader` мерил высоту, `@State` её хранил, а `padding`
    /// прибавлял. Доккомментарий у того механизма сам называл цену:
    /// «пока одно место решает высоту панели, а другое — запас под неё,
    /// они разойдутся, и разойдутся молча».
    ///
    /// Они и расходились. Замер сессии узкого экрана 25.10.2026:
    /// на iPhone SE «Потом, в настройках» ложилось **поверх абзаца**;
    /// на широком экране этого не было, то есть дефект именно узкого.
    /// Сессия крупного кегля померила вторую половину: на AX5 панель
    /// занимает ~160 из 874 pt, и текст режется о непрозрачную кнопку
    /// при любом положении прокрутки.
    ///
    /// # Решение дизайна, круг 6, пункт 8
    ///
    /// Дословно: «Каркас один на тринадцать экранов: содержимое
    /// в `ScrollView`, кнопки в `.safeAreaInset(edge: .bottom)`
    /// на сплошном фоне экрана. Разделитель `line.separator` — только
    /// когда под ним есть текст. **Материал не берём: это новая
    /// поверхность и прозрачность.** То же правило уже утверждено
    /// для клавиатуры (круг 5, п. 1)».
    ///
    /// > **`safeAreaInset` не кладёт панель поверх — он УМЕНЬШАЕТ
    /// > область прокрутки.** Поэтому ручной замер высоты уходит
    /// > целиком: `GeometryReader`, `@State высотаНиза` и `запасПодНизом`
    /// > существовали ровно затем, чтобы повторить то, что система
    /// > делает сама. Два места, решавшие одну величину, стали одним.
    ///
    /// Соседний `TGSheet.footerBar` берёт `.regularMaterial`,
    /// и расхождение теперь ОСОЗНАННОЕ: лист лежит поверх экрана,
    /// у него прозрачность уместна; экран — нижняя поверхность,
    /// и новой над ней не заводится.
    ///
    /// # Разделитель
    ///
    /// Условие «только когда под ним есть текст» каркас проверить
    /// не может: `bottom` приходит замыканием, и что внутри — он
    /// не знает. Поэтому доводом `разделитель`, и по умолчанию он
    /// ВЫКЛЮЧЕН — так сказано в ответе: «только когда под ним есть
    /// текст».
    ///
    /// > **Умолчание исполняет решение или переворачивает его.**
    /// > Первая моя редакция ставила `true`, то есть рисовала линию
    /// > у всех девяти слотов — ровно обратное «только когда».
    /// > Довод с умолчанием «как удобнее» тихо отменяет условие,
    /// > под которым он заведён.
    @ViewBuilder
    private var нижняяПанель: some View {
        if Bottom.self != EmptyView.self {
            VStack(spacing: 0) {
                if разделитель {
                    Rectangle()
                        .fill(Token.Surface.hairline)
                        .frame(height: Token.Size.hairline)
                }
                VStack(spacing: Token.Space.s8) { bottom }
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .padding(.top, Token.Space.s10)
                    .padding(.bottom, Token.Space.s8)
            }
            .background(Token.Surface.screen)
        }
    }
}

extension TGScreen where Bottom == EmptyView {
    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, bottom: { EmptyView() })
    }
}
