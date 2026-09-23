import SwiftUI
import SwiftData

/// Запас таблеток.
///
/// Из хендофа (18f): «Дыра, которой не было в списке: пропуски чаще
/// случаются не из забывчивости, а потому что таблетки кончились
/// в пятницу вечером. Счётчик живёт на отметках — отдельного учёта
/// не нужно».
struct PillSupplyScreen: View {
    let medication: Medication
    var courseEnds: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var supply: PillSupply? {
        PillSupplyAdvisor.supply(left: medication.stockLeft,
                                 total: medication.stockTotal,
                                 timesPerDay: max(1, medication.times.count),
                                 courseEnds: courseEnds)
    }

    var body: some View {
        TGSheet(title: supply.map { LocalizedStringKey.готовая($0.headline) } ?? "Запас таблеток",
                subtitle: subtitle.map { .готовая($0) }) {
            if let supply {
                countCard(supply)
            } else {
                startCard
            }
            addCard
            TGExplainer(text: "Счёт живёт на отметках приёма: минус одна с каждой. Отдельно ничего вести не надо.")
        }
        .presentationDetents([.medium, .large])
    }

    private var subtitle: String? {
        guard let supply else { return "включи счёт — предупредим заранее" }
        if let shortfall = supply.shortfallDays, let ends = courseEnds {
            return "Курс идёт до \(Fmt.shortDay(ends)) — не хватит \(Fmt.days(shortfall)). Аптеки везут 2–3 дня."
        }
        return supply.lastDay.map { "хватит до \(Fmt.shortDay($0))" }
    }

    private func countCard(_ supply: PillSupply) -> some View {
        TGCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(supply.left)").textStyle(AppFont.display)
                Text("из \(supply.total)").textStyle(AppFont.caption)
                Spacer()
                if PillSupplyAdvisor.needsWarning(supply) {
                    Text("пора покупать")
                        .textStyle(AppFont.caption.color(Token.Status.waitingText))
                }
            }
            ProgressView(value: Double(supply.left), total: Double(max(supply.total, supply.left)))
                .tint(PillSupplyAdvisor.needsWarning(supply) ? Token.Status.waitingText : Token.Action.doneText)
        }
    }

    private var startCard: some View {
        TGCard {
            Text("Счёт веду сама").textStyle(AppFont.cardTitle)
            Text("Скажи, сколько таблеток в пачке — дальше приложение будет вычитать по одной с каждой отметки и предупредит за три дня до конца.")
                .textStyle(AppFont.caption)
        }
    }

    private var addCard: some View {
        TGCard {
            TGSectionHeader(title: "новая пачка")
            HStack(spacing: Token.Space.s12) {
                ForEach([30, 60], id: \.self) { count in
                    TGButton(title: "+ \(count) шт", variant: .secondary,
                             size: .medium, fullWidth: false) {
                        add(count)
                    }
                }
                Spacer(minLength: 0)
            }
            TGStepper(value: Binding(get: { medication.stockLeft },
                                     set: { medication.stockLeft = $0; save() }),
                      unit: "шт", step: 1, range: 0...500, compact: true)
        }
    }

    private func add(_ count: Int) {
        medication.stockLeft += count
        medication.stockTotal = max(medication.stockTotal, medication.stockLeft)
        save()
        Haptics.success()
    }

    private func save() { try? context.save() }
}
