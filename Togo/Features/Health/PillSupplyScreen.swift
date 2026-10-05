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
        PillSupplyAdvisor.supply(remaining: medication.remaining,
                                 packSize: medication.packSize,
                                 perDay: medication.dailyUse,
                                 courseEnds: courseEnds ?? medication.courseEnd)
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
        guard let supply else { return String(localized: "включи счёт — предупредим заранее") }
        if let shortfall = supply.shortfallDays, let ends = courseEnds {
            return String(localized: "Курс идёт до \(Fmt.shortDay(ends)) — не хватит \(Fmt.days(shortfall)). Аптеки везут 2–3 дня.")
        }
        return supply.lastDay.map { String(localized: "хватит до \(Fmt.shortDay($0))") }
    }

    /// Числа здесь целые нарочно, хотя запас уже дробный.
    ///
    /// `«\(осталось)»` и `«из \(впачке)»` — ключи каталога
    /// с `%lld`. Подставить сюда `Double` значит завести **новые**
    /// ключи и в ту же секунду получить пробелы в `fr`, `uk` и `en`:
    /// пробел откатывается на русский, и француз увидел бы русскую
    /// строку, а выглядело бы это намеренным выбором, а не пропуском.
    /// Дробный показ («6,5 мл») приедет вместе с единицами и подписями
    /// кадра 30, когда будет кому перевести; до тех пор капли округлятся
    /// вниз — в ту же сторону, что и `days`.
    private func countCard(_ supply: PillSupply) -> some View {
        let осталось = Int(supply.remaining.rounded(.down))
        let впачке = Int(supply.packSize.rounded(.down))
        return TGCard {
            let уровень = PillSupplyAdvisor.level(supply)
            HStack(alignment: .firstTextBaseline) {
                Text("\(осталось)").textStyle(AppFont.display)
                Text("из \(впачке)").textStyle(AppFont.caption)
                Spacer()
                if уровень != .ok {
                    Text("пора покупать")
                        .textStyle(AppFont.caption.color(уровень.цветТекста))
                }
            }
            ProgressView(value: supply.remaining,
                         total: max(supply.packSize, supply.remaining))
                .tint(уровень.цветТекста)
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
            TGStepper(value: Binding(get: { Int(medication.remaining.rounded(.down)) },
                                     set: { установить($0); save() }),
                      unit: "шт", step: 1, range: 0...500, compact: true)
        }
    }

    private func add(_ count: Int) {
        установить(Int(medication.remaining.rounded(.down)) + count)
        save()
        Haptics.success()
    }

    /// Запас пишется в ОБЕ формы, а не в ту, которую читает этот экран.
    ///
    /// `remaining` отдаёт `stockLeftAmount ?? Double(stockLeft)` — то есть
    /// у препарата с дробным учётом целое поле становится мёртвым.
    /// Пиши сюда один `stockLeft`, и у такого препарата кнопка «+ 30 шт»
    /// нажималась бы, сохранялась бы и **не меняла число на экране**:
    /// человек видит прежний остаток и жмёт снова.
    ///
    /// Сегодня `stockLeftAmount` не заполняет ни один экран, так что
    /// расхождения ещё нет. Включит его первый, кто заведёт дробный
    /// учёт, — и включит молча, поэтому обе формы двигаются здесь
    /// вместе, а не «когда понадобится».
    ///
    /// Просится в `Medication` отдельным методом: писателей будет больше
    /// одного (шторка «Купил» с кадра 33), а правило у них одно.
    /// Модель — слой togo-45, заявка отправлена.
    private func установить(_ остаток: Int) {
        medication.stockLeft = остаток
        medication.stockTotal = max(medication.stockTotal, остаток)
        if medication.stockLeftAmount != nil {
            medication.stockLeftAmount = Double(остаток)
        }
        if medication.packAmount != nil {
            medication.packAmount = max(medication.packSize, Double(остаток))
        }
    }

    /// Запас таблеток: «сохранилось» без записи — это человек, который
    /// думает, что таблетки посчитаны, и пропускает докупку.
    private func save() {
        if !context.persist(otherwise: {}) { Haptics.warning() }
    }
}

/// Цвет уровня запаса — **одно место на всё приложение**.
///
/// Мест, где запас красится, уже два (шторка и строка в списке
/// препаратов), а скоро будет больше: экран «Запас», виджет и
/// уведомление «Купил» с кадров 30–33 и 46–48. Повтори это правило
/// в каждом — и оно разойдётся молча, как уже расходилось «не кормить»
/// в трёх реализациях, из которых две молчали.
///
/// Соответствие — с кадра 30, а не по вкусу: ≤ 3 дня терракотом,
/// ≤ 7 оранжевым, дальше нейтрально. Четвёртый цвет (`stockLow`)
/// завёл менеджер 05.10 вечером; до того уровень `.low` вычислялся,
/// а покрасить его было нечем — примитив без семантического имени
/// не доезжает до слоя вида.
///
/// Просится в `Togo/DesignSystem/` — это зона togo-5a; здесь лежит
/// временно, чтобы правило было в одном месте, а не в двух.
extension PillSupplyAdvisor.Level {
    var цветТекста: Color {
        switch self {
        case .ok: Token.Action.doneText
        case .low: Token.Status.stockLowText
        case .urgent: Token.Status.overdueText
        }
    }
}
