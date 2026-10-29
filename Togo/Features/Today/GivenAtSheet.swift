import SwiftUI

/// «Когда дали?» — шторка отметки задним числом.
///
/// Появляется, только когда назначенное время уже прошло больше чем
/// на `LateMarking.grace`. Правило живёт в `LateMarking`, а не здесь:
/// его надо сторожить тестом, а вью тестом не построишь.
///
/// Первым стоит **назначенное время**, а не «сейчас». Это и есть
/// частый случай: человек открыл приложение через два часа после
/// того, как дал таблетку, и хочет записать её тем часом, которым дал.
/// «Сейчас» рядом — на случай, когда опоздала сама выдача, а не отметка.
struct GivenAtSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// Назначенный час пункта плана.
    let scheduled: Date
    /// «Сейчас» — и **пусто, когда показывают прошлый день**.
    ///
    /// Это не мелочь: листая вчера, человек видит вчерашний план,
    /// и строка «Сейчас, 09:30» записала бы сегодняшнее время
    /// в позавчерашнюю еду. В прошлом дне «сейчас» не существует,
    /// и предлагать его нельзя — можно только назвать час.
    ///
    /// Передаётся снаружи и не тикает: иначе выбранное «сейчас»
    /// и записанное «сейчас» разъедутся на границе минуты — на этом
    /// Togo уже обжигался, баннер сказал «в 14:03», а лента в ту же
    /// секунду «14:04».
    let сейчас: Date?
    /// Позже этого записывать нельзя: конец показываемого дня, а сегодня —
    /// текущий момент. Запись в будущем ломает всё, что считается
    /// «от последнего раза».
    let предел: Date
    var onPick: (Date) -> Void

    private enum Choice: Hashable { case scheduled, now, custom }

    @State private var choice: Choice = .scheduled
    @State private var custom: Date

    init(title: String, scheduled: Date, сейчас: Date?, предел: Date,
         onPick: @escaping (Date) -> Void) {
        self.title = title
        self.scheduled = scheduled
        self.сейчас = сейчас
        self.предел = предел
        self.onPick = onPick
        // Ползунок «другого времени» начинается от назначенного: от него
        // и отсчитывают, когда правят.
        _custom = State(initialValue: min(scheduled, предел))
    }

    var body: some View {
        TGSheet(title: "Когда дали?", subtitle: .готовая(title)) {
            TGCard(padding: Token.Space.s4) {
                VStack(spacing: 0) {
                    // Обе строки шли обычной интерполяцией и в каталог
                    // не попадали никогда, при том что соседняя строка
                    // ниже (`Другое время`) обёрнута правильно —
                    // **половина пары в одном `VStack`**. Параметр
                    // у `row` типа `String`, а не `LocalizedStringKey`,
                    // поэтому компилятор на это не покраснеет: склеенная
                    // строка подходит по типу идеально.
                    row(.scheduled, text: String(localized: "В \(Fmt.clock(scheduled)), как назначено"))
                    if let сейчас {
                        TGDivider()
                        row(.now, text: String(localized: "Сейчас, \(Fmt.clock(сейчас))"))
                    }
                    TGDivider()
                    row(.custom, text: String(localized: "Другое время"))

                    if choice == .custom {
                        TGDivider()
                        DatePicker("Время", selection: Binding(
                            get: { min(custom, предел) },
                            set: { custom = min($0, предел) }
                        ), in: ...предел, displayedComponents: .hourAndMinute)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                    }
                }
                .padding(.horizontal, Token.Space.s12)
            }

            TGButton(title: "Записать", variant: .primary, size: .medium) {
                onPick(picked)
                dismiss()
            }

            TGExplainer(text: "От времени дозы считается окно натощак и защита от двойной дозы, от времени еды — «пора ли кормить». Поэтому спрашиваем, а не ставим час нажатия.")
        }
    }

    private var picked: Date {
        switch choice {
        case .scheduled: min(scheduled, предел)
        // «Сейчас» выбрать нельзя, когда его нет: строки для него
        // не нарисовано. Откат на назначенное, а не на `Date()`, —
        // иначе прошлый день молча получил бы сегодняшний час.
        case .now: сейчас ?? min(scheduled, предел)
        case .custom: min(custom, предел)
        }
    }

    /// Строка выбора. Галочка, а не только заливка: направление выбора
    /// не передаётся одним цветом — у Togo это уже записанное правило.
    private func row(_ value: Choice, text: String) -> some View {
        Button {
            choice = value
        } label: {
            HStack(spacing: Token.Space.s8) {
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: Token.Size.iconSm, weight: .bold))
                    .foregroundStyle(choice == value ? Token.Action.doneText : Token.Ink.secondary)
                    .accessibilityHidden(true)
                Text(text).textStyle(AppFont.body)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? [.isButton, .isSelected] : .isButton)
    }
}
