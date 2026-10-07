import Testing
import Foundation
@testable import Togo

/// Плакат: какой цвет несёт блок состояния. Решение дизайна окт 2026.
///
/// Проверяется **порядок**, а не только исходы: у правила пять режимов
/// и четыре из них могут быть верны одновременно, так что ценность
/// теста — в парах «верно сразу два, что победит».
@Suite("Плакат · режим блока состояния")
struct PosterModeTests {

    @Test("Каждый режим достижим, и их ровно пять")
    func everyModeReachable() {
        // Первой — проверка, что набору было что проверять: без неё
        // остальные зеленели бы на урезанном перечислении.
        #expect(PosterMode.allCases.count == 5)

        #expect(PosterMode.mode(.init()) == .usual)
        #expect(PosterMode.mode(.init(isFasting: true)) == .fasting)
        #expect(PosterMode.mode(.init(isDoseDue: true)) == .dose)
        #expect(PosterMode.mode(.init(isAlarm: true)) == .alarm)
        #expect(PosterMode.mode(.init(isNight: true)) == .quiet)
        #expect(PosterMode.mode(.init(isFirstDay: true)) == .quiet)
    }

    @Test("Тревога сильнее всего — даже ночью и даже в час дозы")
    func alarmWinsOverEverything() {
        // Это единственное состояние, из-за которого берут телефон,
        // когда с собакой плохо.
        #expect(PosterMode.mode(.init(isAlarm: true, isNight: true)) == .alarm)
        #expect(PosterMode.mode(.init(isAlarm: true, isDoseDue: true)) == .alarm)
        #expect(PosterMode.mode(.init(isAlarm: true, isFasting: true, isNight: true,
                                      isFirstDay: true)) == .alarm)
    }

    @Test("Ночь сильнее дозы: акцентная заливка во весь верх в три ночи — свет в лицо")
    func nightWinsOverDose() {
        #expect(PosterMode.mode(.init(isDoseDue: true, isNight: true)) == .quiet)
        #expect(PosterMode.mode(.init(isFasting: true, isNight: true)) == .quiet)
        // Переставь две проверки местами — и этот тест покраснеет
        // раньше, чем человек увидит заливку ночью.
    }

    @Test("Доза сильнее натощак: окно ВЕДЁТ к дозе, и когда час пришёл, оно не главное")
    func doseWinsOverFasting() {
        #expect(PosterMode.mode(.init(isFasting: true, isDoseDue: true)) == .dose)
    }

    @Test("Первый день нейтрален, даже если натощак")
    func firstDayIsQuiet() {
        #expect(PosterMode.mode(.init(isFasting: true, isFirstDay: true)) == .quiet)
    }

    @Test("Инверсная подпись ровно у одного режима")
    func onlyDoseInvertsLabel() {
        let инверсные = PosterMode.allCases.filter(\.needsInverseLabel)
        #expect(инверсные == [.dose])
        // От обратного: если инверсных станет два, вью покрасит
        // подпись не тем токеном на одном из них, и кадр это покажет
        // позже теста.
        #expect(инверсные.count == 1)
    }

    @Test("Цвет состояния несут все режимы, кроме тихого")
    func onlyQuietCarriesNoStatusColour() {
        let без = PosterMode.allCases.filter { !$0.carriesStatusColour }
        #expect(без == [.quiet])
    }

    @Test("Пустое состояние даёт обычный режим, а не тихий")
    func emptyStateIsUsualNotQuiet() {
        // Отличать «ничего не происходит» от «ночь» обязательно:
        // иначе днём без событий человек получит нейтральный блок
        // и решит, что приложение не работает.
        #expect(PosterMode.mode(.init()) == .usual)
        #expect(PosterMode.mode(.init()) != .quiet)
    }
}
