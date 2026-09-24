import SwiftUI

/// Секундомер идущей прогулки.
///
/// Считает система, а не приложение. Раньше цифра перерисовывалась вместе
/// с главным экраном — раз в тридцать секунд, — и выглядела застывшей:
/// человек смотрит на неё именно чтобы увидеть, что время идёт.
///
/// Чаще перерисовывать экран было бы неправильно: раз в секунду будить
/// весь `TodayScreen` ради одной строки — это разряженная батарея.
/// `Text(_:style:.timer)` система обновляет сама и без нашего участия.
struct TGStopwatch: View {
    /// Начало прогулки с учётом пауз: система считает от даты вперёд,
    /// поэтому на паузах начало сдвигается.
    let effectiveStart: Date
    let isPaused: Bool
    /// Сколько уже нагуляли — показывается, пока стоим на паузе.
    let frozen: TimeInterval
    var style: TextStyleToken

    var body: some View {
        Group {
            if isPaused {
                // На паузе время не идёт, и бегущая цифра врала бы.
                Text(Fmt.stopwatch(frozen))
            } else {
                Text(effectiveStart, style: .timer)
            }
        }
        .textStyle(style)
        .monospacedDigit()
        // Секундомер не переносится: «1 ч 48 мин» героем шире экрана,
        // и разрыв приходится на середину числа. То же место, что
        // и у соседней ветки героя, — чиним обе, а не ту, о которой
        // пришёл кадр.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // Цифры не должны дёргать соседей при смене ширины.
        .contentTransition(.numericText())
        .accessibilityLabel(isPaused
                            ? "На паузе, \(Fmt.duration(frozen))"
                            : "Идёт \(Fmt.duration(frozen))")
    }

    /// Собрать из идущей сессии.
    init(session: ActiveSession, now: Date = Date(), style: TextStyleToken) {
        let elapsed = session.duration(at: now)
        self.effectiveStart = now.addingTimeInterval(-elapsed)
        self.isPaused = session.isPaused
        self.frozen = elapsed
        self.style = style
    }
}
