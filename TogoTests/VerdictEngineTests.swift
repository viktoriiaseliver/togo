import Testing
import Foundation
@testable import Togo

/// Вердикт «просится» — единственное место, где приложение делает вывод
/// за человека. Поэтому у него больше всего тестов.
@Suite("Вердикт «просится»")
struct VerdictEngineTests {
    private let hour: TimeInterval = 3600

    /// Ровные интервалы по четыре часа: обычный режим взрослой собаки.
    private func steadySignals(
        sinceUrine: TimeInterval,
        days: Int = 10,
        episodeActive: Bool = false,
        lastOutingHadResult: Bool = true
    ) -> NeedSignals {
        let now = Date()
        return NeedSignals(
            now: now,
            lastUrine: now.addingTimeInterval(-sinceUrine),
            lastStool: now.addingTimeInterval(-6 * hour),
            lastMeal: now.addingTimeInterval(-8 * hour),
            lastWalk: now.addingTimeInterval(-3 * hour),
            urineIntervals: Array(repeating: 4 * hour, count: 12),
            daysOfData: days,
            episodeActive: episodeActive,
            lastOutingHadResult: lastOutingHadResult
        )
    }

    @Test("Меньше четырёх дней данных — всегда «непонятно»")
    func notEnoughData() {
        for days in 1...3 {
            let verdict = VerdictEngine.evaluate(steadySignals(sinceUrine: 9 * hour, days: days))
            #expect(verdict == .unknown(reason: .notEnoughData(days: days)))
        }
    }

    @Test("Дольше, чем он когда-либо терпел — «выведи сейчас»")
    func urgent() {
        #expect(VerdictEngine.evaluate(steadySignals(sinceUrine: 7 * hour)) == .urgent)
    }

    @Test("Дольше обычного, но не рекорд — «похоже на нужду»")
    func likelyNeed() {
        // Типичный интервал 4 ч, рекорд 6 ч. Пять часов — дольше обычного
        // (порог 4 ч × 1,15 = 4,6 ч), но до рекорда не дотягивает.
        let now = Date()
        let signals = NeedSignals(
            now: now,
            lastUrine: now.addingTimeInterval(-5 * hour),
            urineIntervals: Array(repeating: 4 * hour, count: 10) + [6 * hour],
            daysOfData: 10,
            lastOutingHadResult: true
        )
        #expect(VerdictEngine.evaluate(signals) == .likelyNeed)
    }

    @Test("Только что вышли и он сходил — «скорее внимания»")
    func probablyAttention() {
        #expect(VerdictEngine.evaluate(steadySignals(sinceUrine: 15 * 60)) == .probablyAttention)
    }

    @Test("Вышли недавно, но без результата — не «скорее внимания»")
    func recentWithoutResult() {
        let verdict = VerdictEngine.evaluate(steadySignals(sinceUrine: 15 * 60, lastOutingHadResult: false))
        #expect(verdict == .unknown(reason: .ambiguous))
    }

    @Test("Эпизод активен — вердикт не считается вовсе")
    func episodeSilencesVerdict() {
        // Даже при рекордном интервале эпизод перебивает всё.
        let verdict = VerdictEngine.evaluate(steadySignals(sinceUrine: 12 * hour, episodeActive: true))
        #expect(verdict == .episode)
    }

    @Test("Во всех исходах первая кнопка — «Вывожу»")
    func outingAlwaysAvailable() {
        let outcomes: [NeedVerdict] = [
            .urgent, .likelyNeed, .unknown(reason: .ambiguous),
            .unknown(reason: .notEnoughData(days: 2)), .probablyAttention, .episode,
        ]
        for verdict in outcomes {
            #expect(!verdict.alternativeAction.isEmpty)
            #expect(!verdict.title.isEmpty)
        }
    }

    @Test("Объяснение всегда непустое и не обещает точности, которой нет")
    func explanationsExist() {
        let signals = steadySignals(sinceUrine: 2 * hour, days: 2)
        let text = VerdictEngine.explanation(VerdictEngine.evaluate(signals), signals)
        #expect(text.contains("мало"))
    }
}
