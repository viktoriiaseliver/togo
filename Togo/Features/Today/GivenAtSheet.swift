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
    /// Момент открытия шторки. Передаётся снаружи и не тикает: иначе
    /// выбранное «сейчас» и записанное «сейчас» разъедутся на границе
    /// минуты — на этом Togo уже обжигался, баннер сказал «в 14:03»,
    /// а лента в ту же секунду «14:04».
    let now: Date
    var onPick: (Date) -> Void

    private enum Choice: Hashable { case scheduled, now, custom }

    @State private var choice: Choice = .scheduled
    @State private var custom: Date

    init(title: String, scheduled: Date, now: Date, onPick: @escaping (Date) -> Void) {
        self.title = title
        self.scheduled = scheduled
        self.now = now
        self.onPick = onPick
        // Ползунок «другого времени» начинается от назначенного: от него
        // и отсчитывают, когда правят.
        _custom = State(initialValue: scheduled)
    }

    var body: some View {
        TGSheet(title: "Когда дали?", subtitle: .готовая(title)) {
            TGCard(padding: 4) {
                VStack(spacing: 0) {
                    row(.scheduled, text: "В \(Fmt.clock(scheduled)), как назначено")
                    TGDivider()
                    row(.now, text: "Сейчас, \(Fmt.clock(now))")
                    TGDivider()
                    row(.custom, text: String(localized: "Другое время"))

                    if choice == .custom {
                        TGDivider()
                        DatePicker("Время", selection: Binding(
                            get: { min(custom, now) },
                            set: { custom = min($0, now) }
                        ), in: ...now, displayedComponents: .hourAndMinute)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                    }
                }
                .padding(.horizontal, 12)
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
        case .scheduled: min(scheduled, now)
        case .now: now
        case .custom: min(custom, now)
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
