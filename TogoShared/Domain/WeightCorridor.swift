import Foundation

/// Коридор веса от врача — как его прочитать из двух полей ввода.
///
/// Коридор показывали экран «Вес» и История, а задать его в приложении
/// было негде: `Dog.targetWeightLow/High` заполняли только пример данных
/// и обмен между телефонами. Правило чтения вынесено сюда, а не оставлено
/// в экране: «пусто — значит коридора нет» и «от меньше до» проверяются
/// тестом, а приватное свойство вида — нет.
nonisolated enum WeightCorridor: Equatable, Sendable {
    /// Оба поля пусты: коридора нет, приложение норму не выдумывает.
    case empty
    case range(low: Double, high: Double)
    case invalid(Reason)

    enum Reason: Equatable, Sendable {
        /// Заполнено одно поле из двух.
        case oneEmpty
        /// Не число или не больше нуля.
        case notNumber
        /// «От» не меньше «до».
        case notAscending
    }

    static func parse(low: String, high: String) -> WeightCorridor {
        let от = low.trimmingCharacters(in: .whitespaces)
        let до = high.trimmingCharacters(in: .whitespaces)
        if от.isEmpty && до.isEmpty { return .empty }
        guard !от.isEmpty, !до.isEmpty else { return .invalid(.oneEmpty) }
        guard let l = number(от), let h = number(до) else { return .invalid(.notNumber) }
        guard l < h else { return .invalid(.notAscending) }
        return .range(low: l, high: h)
    }

    /// Запятая и точка — обе: десятичная клавиатура ставит ту, что
    /// принята в языке телефона.
    private static func number(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Что сохранить в `Dog`: пара границ или пусто. У неверного ввода
    /// сохранять нечего — `nil` снаружи.
    var bounds: (low: Double?, high: Double?)? {
        switch self {
        case .empty: return (low: nil, high: nil)
        case .range(let low, let high): return (low: low, high: high)
        case .invalid: return nil
        }
    }
}
