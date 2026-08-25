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
    /// Сколько упаковок осталось. Дробное, потому что мешок початый.
    var packsLeft: Double = 1
    var openedAt: Date?
    /// Сколько граммов этого корма собака получает в день.
    /// Для смешанного кормления у каждого корма своя цифра.
    var gramsPerDay: Int = 0

    var dog: Dog?

    init(kind: FoodKind, brand: String = "", packGrams: Int, packsLeft: Double, gramsPerDay: Int) {
        self.kindRaw = kind.rawValue
        self.brand = brand
        self.packGrams = packGrams
        self.packsLeft = packsLeft
        self.gramsPerDay = gramsPerDay
    }

    var kind: FoodKind {
        get { FoodKind(rawValue: kindRaw) ?? .dry
        }
        set { kindRaw = newValue.rawValue }
    }

    var remainingGrams: Int { Int(packsLeft * Double(packGrams)) }

    /// На сколько дней хватит при текущей норме.
    var daysLeft: Int? {
        guard gramsPerDay > 0 else { return nil }
        return remainingGrams / gramsPerDay
    }

    func runsOutOn(from date: Date = Date()) -> Date? {
        guard let daysLeft else { return nil }
        return Calendar.current.date(byAdding: .day, value: daysLeft,
                                     to: Calendar.current.startOfDay(for: date))
    }

    /// Пора покупать. Неделя — чтобы успеть заказать и не переводить
    /// собаку на другой корм резко.
    var needsRestock: Bool { (daysLeft ?? 99) <= 7 }

    /// Сколько упаковок купить, чтобы хватило на столько-то дней.
    func packsNeeded(forDays days: Int) -> Int {
        guard gramsPerDay > 0, packGrams > 0 else { return 0 }
        let need = Double(gramsPerDay * days) - Double(remainingGrams)
        guard need > 0 else { return 0 }
        return Int((need / Double(packGrams)).rounded(.up))
    }

    /// Сколько упаковок уходит в день — для влажного это осмысленная цифра.
    var packsPerDay: Double? {
        guard packGrams > 0, gramsPerDay > 0 else { return nil }
        return Double(gramsPerDay) / Double(packGrams)
    }

    var summary: String {
        let unit = kind.unitName(count: packsLeft)
        if kind == .dry {
            return String(format: "%.1f %@ · %d г в день", packsLeft, unit, gramsPerDay)
        }
        return String(format: "%.0f %@ по %d г", packsLeft, unit, packGrams)
    }
}

nonisolated enum FoodKind: String, Codable, CaseIterable, Sendable {
    case dry
    case wet

    var title: String {
        switch self {
        case .dry: "Сухой"
        case .wet: "Влажный"
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
        case .dry: return Fmt.plural(Int(count.rounded()), "мешок", "мешка", "мешков")
                            .components(separatedBy: " ").last ?? "мешок"
        case .wet: return Fmt.plural(Int(count.rounded()), "банка", "банки", "банок")
                            .components(separatedBy: " ").last ?? "банка"
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
            ? String(format: "%.1f кг", Double(grams) / 1000).replacingOccurrences(of: ".0", with: "")
            : "\(grams) г"
    }

    /// То, что нельзя не сказать при переходе на влажный.
    var caution: String? {
        switch self {
        case .wet:
            "Влажный корм — это в основном вода: та же цифра на весах даёт заметно меньше еды, чем сухой. Норму бери с упаковки или у врача, а не переноси граммы из сухого."
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
            needsRestock: stocks.contains(where: \.needsRestock)
        )
    }
}
