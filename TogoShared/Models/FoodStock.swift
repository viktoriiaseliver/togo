import Foundation
import SwiftData

/// Чем кормят и в какой фасовке.
///
/// Сухой корм берут мешками по несколько килограммов, влажный — банками
/// и паучами по 100–500 граммов, и очень часто дают и то и другое. Считать
/// «сколько осталось» в килограммах для влажного бессмысленно: человек
/// думает банками.
///
/// Важное, чего приложение не имеет права забыть: **граммы сухого
/// и влажного не равны**. Влажный — это на три четверти вода, и та же
/// цифра на весах даёт втрое меньше еды. Поэтому норма для каждого корма
/// своя, и берётся она с упаковки или у врача.
@Model
final class FoodStock {
    var id: UUID = UUID()
    var kindRaw: String = FoodKind.dry.rawValue
    var brand: String = ""
    /// Размер одной упаковки в граммах: мешок, банка, пауч.
    var packGrams: Int = 3000
    /// Сколько упаковок было **на дату пересчёта**. Дробное, потому что
    /// мешок початый.
    var packsLeft: Double = 1
    /// Когда человек в последний раз сказал, сколько осталось. От этой даты
    /// и считается расход: без неё цифра «хватит на N дней» замирает
    /// навсегда и врёт уже на следующий день.
    var countedAt: Date?
    var openedAt: Date?

    /// Годен до — с упаковки.
    var expiry: Date?

    /// Сколько дней годен после вскрытия.
    ///
    /// **Открытый мешок портится раньше, чем кончается.** Сухой корм
    /// на воздухе окисляется за полтора-два месяца, и у большой фасовки
    /// это наступает прежде, чем собака его доест. Поэтому срок после
    /// вскрытия — отдельное поле, а не то же, что `expiry`: тумблер
    /// «Сразу вскрыл» в шторке «Купил» переключает одно в другое.
    ///
    /// Ноль — срок после вскрытия не задан, действует только `expiry`.
    var shelfAfterOpenDays: Int = 0
    /// Сколько граммов этого корма собака получает в день.
    /// Для смешанного кормления у каждого корма своя цифра.
    var gramsPerDay: Int = 0

    var dog: Dog?

    init(
        kind: FoodKind,
        brand: String = "",
        packGrams: Int,
        packsLeft: Double,
        gramsPerDay: Int,
        countedAt: Date = Date()
    ) {
        self.kindRaw = kind.rawValue
        self.brand = brand
        self.packGrams = packGrams
        self.packsLeft = packsLeft
        self.gramsPerDay = gramsPerDay
        self.countedAt = countedAt
    }

    var kind: FoodKind {
        get { FoodKind(rawValue: kindRaw) ?? .dry
        }
        set { kindRaw = newValue.rawValue }
    }

    /// Сколько было на момент пересчёта.
    var countedGrams: Int { Int(packsLeft * Double(packGrams)) }

    /// Сколько съедено с тех пор.
    func usedGrams(at now: Date = Date()) -> Int {
        guard let countedAt, gramsPerDay > 0 else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: countedAt),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return min(countedGrams, max(0, days) * gramsPerDay)
    }

    /// Сколько осталось сейчас.
    func remainingGrams(at now: Date = Date()) -> Int {
        max(0, countedGrams - usedGrams(at: now))
    }

    /// На сколько дней хватит при текущей норме.
    func daysLeft(at now: Date = Date()) -> Int? {
        guard gramsPerDay > 0 else { return nil }
        return remainingGrams(at: now) / gramsPerDay
    }

    func runsOutOn(from date: Date = Date()) -> Date? {
        guard let days = daysLeft(at: date) else { return nil }
        return Calendar.current.date(byAdding: .day, value: days,
                                     to: Calendar.current.startOfDay(for: date))
    }

    /// Насколько плохо с кормом — **той же лестницей, что у таблеток**.
    ///
    /// До 07.10.2026 здесь стоял свой порог `<= 7` и отдавалось булево.
    /// Лестница `ok · low · urgent · out` у проекта была —
    /// `PillSupplyAdvisor.Level`, с порогами 7 и 3, — и до корма
    /// не дотянулась: наш класс «починка на одной поверхности из двух».
    /// Цена была видимой: «кончается через неделю» и «кончается завтра»
    /// красились одним цветом, потому что различать было нечем.
    ///
    /// Порог здесь не повторяется — он спрашивается. Два правила
    /// на одну мысль расходятся на второй правке.
    func level(at now: Date = Date()) -> PillSupplyAdvisor.Level {
        guard let days = daysLeft(at: now) else { return .ok }
        return PillSupplyAdvisor.level(days: days)
    }

    /// Пора покупать. Неделя — чтобы успеть заказать и не переводить
    /// собаку на другой корм резко.
    ///
    /// Определена через `level`, а не рядом с ним: пока у вопроса
    /// «предупреждаем?» есть свои вызовы, он обязан отвечать тем же
    /// правилом, что и цвет. Своего порога у него больше нет.
    func needsRestock(at now: Date = Date()) -> Bool { level(at: now) != .ok }

    /// Сколько упаковок осталось сейчас — для влажного это осмысленная цифра.
    func packsRemaining(at now: Date = Date()) -> Double {
        guard packGrams > 0 else { return 0 }
        return Double(remainingGrams(at: now)) / Double(packGrams)
    }

    /// Сколько упаковок купить, чтобы хватило на столько-то дней.
    func packsNeeded(forDays days: Int, at now: Date = Date()) -> Int {
        guard gramsPerDay > 0, packGrams > 0 else { return 0 }
        let need = Double(gramsPerDay * days) - Double(remainingGrams(at: now))
        guard need > 0 else { return 0 }
        return Int((need / Double(packGrams)).rounded(.up))
    }


    /// Сколько упаковок уходит в день — для влажного это осмысленная цифра:
    /// человек думает банками, а не граммами.
    var packsPerDay: Double? {
        guard packGrams > 0, gramsPerDay > 0 else { return nil }
        return Double(gramsPerDay) / Double(packGrams)
    }

    func summary(at now: Date = Date()) -> String {
        let left = packsRemaining(at: now)
        let unit = kind.unitName(count: left)
        if kind == .dry {
            // «0 г в день» значит «расход не задан», а читается как
            // «не ест». Расход единственного корма приезжает из дневной
            // нормы (`Dog.syncSingleFoodShare`), и при ненаписанной
            // норме он ноль по устройству — то есть ноль тут отвечает
            // про наш пробел, а не про собаку.
            guard gramsPerDay > 0 else {
                return String(format: String(localized: "%.1f %@ · расход не задан"), left, unit)
            }
            return String(format: String(localized: "%.1f %@ · %d г в день"), left, unit, gramsPerDay)
        }
        return String(format: String(localized: "%.0f %@ по %d г"), left.rounded(), unit, packGrams)
    }
}

nonisolated enum FoodKind: String, Codable, CaseIterable, Sendable {
    case dry
    case wet

    var title: String {
        switch self {
        case .dry: String(localized: "Сухой")
        case .wet: String(localized: "Влажный")
        }
    }

    var symbol: String {
        switch self {
        case .dry: "shippingbox"
        case .wet: "takeoutbag.and.cup.and.straw"
        }
    }

    /// Как называть упаковку. Мешок и банка — разные вещи, и человек
    /// думает именно этими словами.
    func unitName(count: Double) -> String {
        switch self {
        case .dry: return String(localized: "\(Int(count.rounded())) мешков")
                            .components(separatedBy: " ").last ?? String(localized: "мешок")
        case .wet: return String(localized: "\(Int(count.rounded())) банок")
                            .components(separatedBy: " ").last ?? String(localized: "банка")
        }
    }

    /// Обычные фасовки. Влажный фасуют мелко, сухой — мешками.
    var commonPackSizes: [Int] {
        switch self {
        case .wet: [85, 100, 150, 200, 300, 400, 500]
        case .dry: [400, 1500, 3000, 6000, 12000, 15000]
        }
    }

    func packLabel(_ grams: Int) -> String {
        grams >= 1000
            ? String(format: String(localized: "%.1f кг"), Double(grams) / 1000).replacingOccurrences(of: ".0", with: "")
            : String(localized: "\(grams) г")
    }

    /// То, что нельзя не сказать при переходе на влажный.
    var caution: String? {
        switch self {
        case .wet:
            String(localized: "Влажный корм — это в основном вода: та же цифра на весах даёт заметно меньше еды, чем сухой. Норму бери с упаковки или у врача, а не переноси из сухого.")
        case .dry:
            nil
        }
    }
}

/// Итог по всем кормам собаки сразу.
nonisolated struct FoodPlan: Equatable, Sendable {
    var totalGramsPerDay: Int
    /// Ближайший день, когда что-то закончится.
    var firstRunOut: Date?
    var whatRunsOutFirst: String?
    var needsRestock: Bool

    static let empty = FoodPlan(totalGramsPerDay: 0, firstRunOut: nil,
                                whatRunsOutFirst: nil, needsRestock: false)
}

nonisolated enum FoodPlanner {
    /// Сколько закупать за раз. Месяц — привычный шаг и для мешка,
    /// и для коробки банок.
    static let planningDays = 30

    @MainActor
    static func plan(_ stocks: [FoodStock], from date: Date = Date()) -> FoodPlan {
        guard !stocks.isEmpty else { return .empty }

        let soonest = stocks
            .compactMap { stock -> (Date, String)? in
                guard let out = stock.runsOutOn(from: date) else { return nil }
                return (out, stock.brand.isEmpty ? stock.kind.title.lowercased() : stock.brand)
            }
            .min { $0.0 < $1.0 }

        return FoodPlan(
            totalGramsPerDay: stocks.map(\.gramsPerDay).reduce(0, +),
            firstRunOut: soonest?.0,
            whatRunsOutFirst: soonest?.1,
            needsRestock: stocks.contains { $0.needsRestock(at: date) }
        )
    }
}
