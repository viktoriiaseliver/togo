import Testing
import Foundation
@testable import Togo

/// Логика медицинского слоя: норма, время забора, срок контроля.
/// ТЗ — `docs/ТЗ-медицинский-слой.md`.
///
/// Числа в тестах — из настоящей карты Стича, на которую ссылается ТЗ,
/// а не выдуманные: Т4 норма 12,9–51,5, значения 6,0 · 10,3 · 14,2 ·
/// 16,7, заборы +3,5 ч и +11,5 ч, ТТГ норма `<0,50`, результат `<0,1`.
/// Синтетика добавлена отдельно там, где настоящие данные случайно
/// маскируют дефект — у нас записано, что ни одна не заменяет другую.
@Suite("Медслой · норма, время забора, срок контроля")
struct MedLayerDomainTests {

    // MARK: Норма и отклонение

    private static let т4 = LabNorm.Reference.range(low: 12.9, high: 51.5)
    private static let ттг = LabNorm.Reference.upperBound(0.50)

    @Test("Отклонение считается из нормы, по всем трём сторонам")
    func deviationFromRange() {
        #expect(LabNorm.deviation(value: .measured(6.0), from: Self.т4) == .below)
        #expect(LabNorm.deviation(value: .measured(16.7), from: Self.т4) == .withinRange)
        #expect(LabNorm.deviation(value: .measured(60.0), from: Self.т4) == .above)
        // Края включительно: 12,9 — это норма, а не «ниже».
        #expect(LabNorm.deviation(value: .measured(12.9), from: Self.т4) == .withinRange)
        #expect(LabNorm.deviation(value: .measured(51.5), from: Self.т4) == .withinRange)
    }

    @Test("Нормы нет — говорим «норма не указана», а не «в норме»")
    func unknownNormIsNotWithinRange() {
        let d = LabNorm.deviation(value: .measured(999), from: .unknown)
        #expect(d == .normUnknown)
        // Это и есть запрет «не придумывать значения»: без нормы
        // приложение не толкует результат ни в какую сторону.
        #expect(d != .withinRange)
        #expect(d != .above)
    }

    @Test("«Меньше предела прибора» — не число 0,1")
    func belowDetectionLimitIsNotANumber() {
        // ТТГ `<0,1` при норме `<0,50`: в норме, предел ниже порога.
        #expect(LabNorm.deviation(value: .belowDetectionLimit(0.1), from: Self.ттг) == .withinRange)
        // Тот же `<0,1` при норме-диапазоне Т4: ниже низа — ниже нормы.
        #expect(LabNorm.deviation(value: .belowDetectionLimit(0.1), from: Self.т4) == .below)
        // А вот «меньше 20» при норме 12,9–51,5 сказать нельзя ничего:
        // оно могло быть и в норме, и под ней. Синтетика: в карте Стича
        // такого случая нет, и именно поэтому он проверяется здесь.
        #expect(LabNorm.deviation(value: .belowDetectionLimit(20), from: Self.т4) == .indeterminate)
    }

    @Test("Отклонение называется словом, и слова различны у всех пяти исходов")
    func everyDeviationHasItsOwnWord() {
        let все: [LabNorm.Deviation] = [.below, .withinRange, .above, .normUnknown, .indeterminate]
        let слова = Set(все.map(LabNorm.word))
        // Одно слово на два исхода — это «один текст на три причины»,
        // за который у Togo уже заплачено.
        #expect(слова.count == все.count)
    }

    @Test("Полоса нормы: у диапазона два края, у порога один, без нормы полосы нет")
    func bandBoundsMatchReferenceShape() {
        let диапазон = LabNorm.bandBounds(Self.т4)
        #expect(диапазон?.low == 12.9)
        #expect(диапазон?.high == 51.5)
        let порог = LabNorm.bandBounds(Self.ттг)
        #expect(порог?.low == nil)
        #expect(порог?.high == 0.50)
        #expect(LabNorm.bandBounds(.unknown) == nil)
    }

    // MARK: Время забора

    @Test("Часы считаются; доза после забора — «не указано», а не минус")
    func hoursSinceDose() {
        let забор = Date(timeIntervalSince1970: 1_790_000_000)
        let доза = забор.addingTimeInterval(-3.5 * 3600)
        #expect(LabSampleTiming.timing(sampledAt: забор, lastDoseAt: доза, hasActiveTreatment: true)
                == .hoursSinceDose(3.5))
        // Доза позже забора — разъехавшиеся часы или доза, данная после.
        // Отрицательное число на подписи прочтут как опечатку.
        #expect(LabSampleTiming.timing(sampledAt: забор,
                                       lastDoseAt: забор.addingTimeInterval(2 * 3600),
                                       hasActiveTreatment: true)
                == .unknownDuringTreatment)
    }

    @Test("Без лечения вопрос не задаётся, а при лечении пропуск виден отдельно")
    func noTreatmentIsNotTheSameAsUnknown() {
        let забор = Date()
        // У здоровой собаки часам неоткуда взяться — это не пропуск.
        #expect(LabSampleTiming.timing(sampledAt: забор, lastDoseAt: nil, hasActiveTreatment: false)
                == .noTreatment)
        // При лечении отсутствие времени — именно пропуск, и он обязан
        // быть отличим: иначе результат притворяется сравнимым.
        #expect(LabSampleTiming.timing(sampledAt: забор, lastDoseAt: nil, hasActiveTreatment: true)
                == .unknownDuringTreatment)
        #expect(LabSampleTiming.Timing.noTreatment != LabSampleTiming.Timing.unknownDuringTreatment)
    }

    @Test("3,5 ч и 11,5 ч несравнимы — это тот самый случай из карты")
    func theCaseFromTheChart() {
        // 07.09.2025: Т4 10,3 при +11,5 ч и Т4 16,7 при +3,5 ч, одна доза.
        // Поставить эти точки рядом как сравнимые — и есть дефект,
        // который случился в карте дважды.
        #expect(!LabSampleTiming.comparable(.hoursSinceDose(3.5), .hoursSinceDose(11.5)))
        // А 3,5 и 5,5 сравнимы: разброс в пределах порога.
        #expect(LabSampleTiming.comparable(.hoursSinceDose(3.5), .hoursSinceDose(5.5)))
    }

    @Test("Любая пара с «не указано» несравнима, и смена режима тоже")
    func unknownIsNeverComparable() {
        #expect(!LabSampleTiming.comparable(.unknownDuringTreatment, .hoursSinceDose(3.5)))
        #expect(!LabSampleTiming.comparable(.unknownDuringTreatment, .unknownDuringTreatment))
        // «Лечение» против «без лечения» — разные режимы, не разброс.
        #expect(!LabSampleTiming.comparable(.noTreatment, .hoursSinceDose(3.5)))
        // Без лечения время ни на что не влияет — сравнимы.
        #expect(LabSampleTiming.comparable(.noTreatment, .noTreatment))
    }

    @Test("Один анализ графиком не рисуется: один результат выглядит как тренд")
    func chartNeedsTwoPoints() {
        #expect(!LabSampleTiming.chartMakesSense(resultCount: 0))
        #expect(!LabSampleTiming.chartMakesSense(resultCount: 1))
        #expect(LabSampleTiming.chartMakesSense(resultCount: 2))
    }

    @Test("Подпись есть там, где есть что сказать, и молчит там, где нечего")
    func captionSpeaksOnlyWhenItHasSomething() {
        #expect(LabSampleTiming.caption(.hoursSinceDose(3.5)) != nil)
        #expect(LabSampleTiming.caption(.unknownDuringTreatment) != nil)
        // Без лечения подписи нет — иначе у здоровой собаки на графике
        // висела бы строка про дозу, которой не было.
        #expect(LabSampleTiming.caption(.noTreatment) == nil)
    }

    // MARK: Срок контроля

    private func календарь() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    @Test("«Через 4–6 недель» — окно, а не дата")
    func windowIsARange() {
        let cal = календарь()
        let назначено = Date(timeIntervalSince1970: 1_790_000_000)
        let окно = ControlWindow.window(prescribedAt: назначено,
                                        .init(fromWeeks: 4, toWeeks: 6),
                                        calendar: cal)
        #expect(окно != nil)
        guard let окно else { return }
        #expect(окно.opens == cal.date(byAdding: .weekOfYear, value: 4, to: назначено))
        #expect(окно.closes == cal.date(byAdding: .weekOfYear, value: 6, to: назначено))
        // «Через 3 недели» — тоже окно, шириной в ноль.
        let одно = ControlWindow.window(prescribedAt: назначено, .init(weeks: 3), calendar: cal)
        #expect(одно?.opens == одно?.closes)
    }

    @Test("Перевёрнутый диапазон не ломается: врач мог написать «6–4»")
    func reversedRangeIsNormalised() {
        let p = ControlWindow.Prescribed(fromWeeks: 6, toWeeks: 4)
        #expect(p.fromWeeks == 4)
        #expect(p.toWeeks == 6)
    }

    @Test("Четыре ступени различимы, и последний день — своя, не часть «открыто»")
    func fourStagesIncludingLastDay() {
        let cal = календарь()
        let назначено = Date(timeIntervalSince1970: 1_790_000_000)
        guard let окно = ControlWindow.window(prescribedAt: назначено,
                                              .init(fromWeeks: 4, toWeeks: 6),
                                              calendar: cal) else {
            Issue.record("окно не посчиталось"); return
        }

        #expect(ControlWindow.stage(окно, now: назначено, calendar: cal)
                == .beforeWindow(opens: окно.opens))
        #expect(ControlWindow.stage(окно, now: окно.opens.addingTimeInterval(3600), calendar: cal)
                == .open(closes: окно.closes))
        #expect(ControlWindow.stage(окно, now: окно.closes, calendar: cal) == .lastDay)
        #expect(ControlWindow.stage(окно, now: окно.closes.addingTimeInterval(48 * 3600), calendar: cal)
                == .missed(closedAt: окно.closes))
    }

    @Test("Напоминаний ровно два, и о прошедшем окне приложение не напоминает")
    func twoRemindersAndNoneAfterwards() {
        let cal = календарь()
        let назначено = Date(timeIntervalSince1970: 1_790_000_000)
        guard let окно = ControlWindow.window(prescribedAt: назначено,
                                              .init(fromWeeks: 4, toWeeks: 6),
                                              calendar: cal) else {
            Issue.record("окно не посчиталось"); return
        }
        #expect(ControlWindow.reminderDates(окно, now: назначено).count == 2)
        // Окно прошло — пушей нет: напоминание о прошедшем сроке это
        // упрёк, а не напоминание. О пропуске говорит экран.
        #expect(ControlWindow.reminderDates(окно, now: окно.closes.addingTimeInterval(3600)).isEmpty)
        // Внутри окна остаётся одно — про последний день.
        #expect(ControlWindow.reminderDates(окно, now: окно.opens.addingTimeInterval(3600)).count == 1)
    }

    @Test("Каждая ступень называется своим словом")
    func everyStageHasItsOwnWord() {
        let сейчас = Date()
        let все: [ControlWindow.Stage] = [.beforeWindow(opens: сейчас), .open(closes: сейчас),
                                          .lastDay, .missed(closedAt: сейчас)]
        #expect(Set(все.map(ControlWindow.word)).count == все.count)
    }

    @Test("Набору было что проверять: домен медслоя")
    func suiteHadSomethingToCheck() {
        #expect(LabSampleTiming.comparableSpreadHours == 3)
        #expect(LabNorm.bandBounds(Self.т4) != nil)
        #expect(ControlWindow.Prescribed(weeks: 3).fromWeeks == 3)
    }
}
