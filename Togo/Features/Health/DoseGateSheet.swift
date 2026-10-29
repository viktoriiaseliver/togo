import SwiftUI

/// Доза ждёт: таймер идёт от отметки еды.
///
/// Инсулин колют не по часам, а через N минут после того, как собака
/// поела. Нажатие по такой дозе не отмечает её, а показывает, чего ждём
/// и с какого момента пошёл отсчёт.
///
/// Отдельный случай — «не поела вовсе». Это не «подожди ещё немного»:
/// цепочка не началась, и решать здесь должен врач.
struct DoseGateSheet: View {
    let medication: Medication
    let state: DoseGate.State
    let now: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGSheet(title: .готовая(medication.name), subtitle: .готовая(medication.doseText)) {
            switch state {
            case .open:
                TGExplainer(text: "Доза открыта — можно отмечать.")
            case .waiting(let until, let since):
                waiting(until: until, since: since)
            case .noMeal:
                noMeal
            }
        } footer: {
            TGButton(title: "Понятно", variant: .secondary, size: .medium) { dismiss() }
        }
        .presentationDetents([.medium])
    }

    private func waiting(until: Date, since: Date) -> some View {
        VStack(spacing: Token.Space.s12) {
            TGCard {
                Text(Fmt.stopwatch(max(0, until.timeIntervalSince(now))))
                    .textStyle(AppFont.hero.color(Token.Status.doneText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("откроется в \(Fmt.clock(until))")
                    .textStyle(AppFont.caption)
            }
            TGCard {
                TGIconRow(symbol: "fork.knife",
                          title: "Ел в \(Fmt.clock(since))",
                          detail: "Отсчёт пошёл с этой отметки, а не с расписания: покормили позже — укол сдвинулся ровно на столько же.")
            }
            TGExplainer(text: "Раньше времени отметить нельзя. Так задумано: \(Fmt.minutes(medication.minutesAfterMeal)) — это условие из назначения.", памятка: "доза.раньшеНельзя")
        }
    }

    private var noMeal: some View {
        VStack(spacing: Token.Space.s12) {
            TGBanner(tone: .waiting,
                     title: "Сегодня ещё не ели",
                     subtitle: "Таймер запускает отметка еды. Пока её нет, доза не откроется.",
                     systemImage: "fork.knife")
            TGCard {
                TGSectionHeader(title: "если собака не ест")
                TGExplainer(text: "Это вопрос к врачу, а не к приложению: колоть в пустой желудок нельзя, а пропускать назначение — решение врача.")
                ShareLink(item: "\(medication.name) \(medication.doseText): собака не ела, доза по условию не открывается. Что делать?") {
                    TGListRow(title: "Спросить врача", systemImage: "square.and.arrow.up",
                              accessory: .none)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
