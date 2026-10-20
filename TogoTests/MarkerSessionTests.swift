import Testing
import Foundation
@testable import Togo

@Suite("Занятие и точность маркера")
@MainActor
struct MarkerSessionTests {
    @Test("До полусекунды — «в момент», после секунды — «поздно»")
    func accuracyThresholds() {
        #expect(MarkAccuracy.from(delayMilliseconds: 120) == .onTime)
        #expect(MarkAccuracy.from(delayMilliseconds: 500) == .onTime)
        #expect(MarkAccuracy.from(delayMilliseconds: 501) == .almost)
        #expect(MarkAccuracy.from(delayMilliseconds: 1000) == .almost)
        #expect(MarkAccuracy.from(delayMilliseconds: 1001) == .late)
    }

    @Test("Задержка считается между «он сделал» и маркером")
    func delayMeasured() {
        let session = MarkerSession()
        let start = Date()
        session.start(at: start)
        session.markAction(at: start.addingTimeInterval(10))
        let accuracy = session.markMarker(at: start.addingTimeInterval(10.3))

        #expect(accuracy == .onTime)
        #expect(session.delaysMs.count == 1)
        #expect(abs(session.delaysMs[0] - 300) <= 2)
        #expect(session.successes == 1)
        #expect(session.attempts == 1)
    }

    @Test("Маркер без «он сделал» ничего не записывает")
    func markerWithoutActionIsIgnored() {
        let session = MarkerSession()
        session.start()
        #expect(session.markMarker() == nil)
        #expect(session.delaysMs.isEmpty)
    }

    @Test("После трёх минут прогресс не пишется")
    func overtimeStopsProgress() {
        let session = MarkerSession(limitMinutes: 3)
        let start = Date()
        session.start(at: start)
        let later = start.addingTimeInterval(181)

        #expect(session.isOvertime(at: later))
        #expect(!session.countsTowardProgress(at: later))
        #expect(session.hint(at: later).contains("заканчивай"))
    }

    @Test("«Не брал еду» снимает оценку целиком")
    func refusedFoodVoidsSession() {
        let session = MarkerSession()
        let start = Date()
        session.start(at: start)
        session.markAction(at: start.addingTimeInterval(1))
        session.markMarker(at: start.addingTimeInterval(1.2))
        session.observations.insert(.refusedFood)

        #expect(!session.countsTowardProgress(at: start.addingTimeInterval(60)))
    }

    @Test("Неудачный повтор увеличивает попытки, но не успехи")
    func missCounts() {
        let session = MarkerSession()
        session.start()
        session.markMiss()
        #expect(session.attempts == 1)
        #expect(session.successes == 0)
        #expect(!session.isWaitingForMark)
    }

    @Test("Шаг закрывается при 4 из 5 в двух занятиях подряд")
    func stepClosesAfterTwoGoodSessions() {
        let step = TrainingStep(cue: "Ко мне", place: "Коридор", person: "Виктория", distanceMeters: 5)
        #expect(!step.isClosed)
        step.consecutiveGoodSessions = 1
        #expect(!step.isClosed)
        step.consecutiveGoodSessions = 2
        #expect(step.isClosed)
    }

    @Test("Занятие 4 из 5 — удачное, 2 из 5 — плохое")
    func sessionQuality() {
        let session = TrainingSession(cue: "Ко мне", place: "дома", person: "Виктория", distanceMeters: 2)
        session.attempts = 5
        session.successes = 4
        #expect(session.isGoodSession)
        #expect(!session.isPoorSession)

        session.successes = 2
        #expect(!session.isGoodSession)
        #expect(session.isPoorSession)
    }
}

@Suite("Уход, дозы и поездка")
@MainActor
struct CareAndDoseTests {
    @Test("Сезонное дело молчит вне сезона")
    func seasonalTask() {
        let task = CareTask(title: "Капли от клещей", detail: "раз в 4 недели",
                            intervalDays: 28, category: .medical)
        task.seasonStartMonth = 4
        task.seasonEndMonth = 10

        let january = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let june = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(!task.isInSeason(on: january))
        #expect(task.isInSeason(on: june))
        #expect(!task.isDue(on: january))
    }

    @Test("Сезон через новый год считается правильно")
    func seasonWrapsYear() {
        let task = CareTask(title: "Что-то зимнее", detail: "", intervalDays: 30, category: .grooming)
        task.seasonStartMonth = 11
        task.seasonEndMonth = 2
        let december = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        let july = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        #expect(task.isInSeason(on: december))
        #expect(!task.isInSeason(on: july))
    }

    @Test("«Беру на себя» живёт 45 минут")
    func claimTTL() {
        let dose = DoseRecord(scheduledAt: Date())
        let claimed = Date()
        dose.claimedBy = "Тео"
        dose.claimedAt = claimed

        #expect(dose.claimIsActive(at: claimed.addingTimeInterval(40 * 60)))
        #expect(!dose.claimIsActive(at: claimed.addingTimeInterval(46 * 60)))
    }

    @Test("Лестница эскалации: ступени −10, +30, +60 по времени")
    func escalationLadder() {
        let scheduled = Date()
        let dose = DoseRecord(scheduledAt: scheduled)

        #expect(dose.escalationStage(at: scheduled.addingTimeInterval(-20 * 60)) == 0)
        #expect(dose.escalationStage(at: scheduled.addingTimeInterval(-5 * 60)) == 1)
        #expect(dose.escalationStage(at: scheduled.addingTimeInterval(35 * 60)) == 2)
        #expect(dose.escalationStage(at: scheduled.addingTimeInterval(70 * 60)) == 3)
    }

    @Test("Отмеченная доза больше не эскалируется")
    func givenDoseStopsEscalation() {
        let scheduled = Date()
        let dose = DoseRecord(scheduledAt: scheduled)
        dose.givenAt = scheduled
        #expect(dose.escalationStage(at: scheduled.addingTimeInterval(120 * 60)) == 0)
    }

    @Test("Сборы считаются из веса и порции, а не из общей таблицы")
    func packingMath() {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.portionGrams = 60
        dog.mealsPerDay = 2

        #expect(dog.dailyGrams == 120)
        #expect(dog.waterNormMl == 205)
    }

    @Test("Поездка знает свой день и длину")
    func tripDays() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 5, to: start)!
        let trip = Trip(destination: "Лион", startDate: start, endDate: end, transport: .car)

        #expect(trip.dayCount() == 6)
        #expect(trip.dayNumber(on: start) == 1)
        #expect(trip.isActive(on: calendar.date(byAdding: .day, value: 2, to: start)!))
    }

    @Test("Роли: помощник не видит медицинского, наблюдатель не пишет")
    func rolePermissions() {
        #expect(!FamilyRole.helper.canSeeMedical)
        #expect(FamilyRole.helper.canWrite)
        #expect(!FamilyRole.observer.canWrite)
        #expect(FamilyRole.observer.canSeeMedical)
        #expect(FamilyRole.owner.canEditTreatment)
        #expect(!FamilyRole.coOwner.canEditTreatment)
    }
}

@Suite("Форматирование")
struct FormattingTests {
    @Test("Русские окончания у чисел")
    func plurals() {
        #expect(Fmt.days(1) == "1 день")
        #expect(Fmt.days(2) == "2 дня")
        #expect(Fmt.days(5) == "5 дней")
        #expect(Fmt.days(11) == "11 дней")
        #expect(Fmt.days(21) == "21 день")
        #expect(Fmt.days(112) == "112 дней")
    }

    @Test("Длительность читается как в макете")
    func durations() {
        #expect(Fmt.duration(0) == "0 мин")
        #expect(Fmt.duration(45 * 60) == "45 мин")
        #expect(Fmt.duration(2 * 3600) == "2 ч")
        #expect(Fmt.duration(5 * 3600 + 20 * 60) == "5 ч 20 мин")
    }

    @Test("Секундомер идёт в минутах и секундах")
    func stopwatch() {
        #expect(Fmt.stopwatch(134) == "2:14")
        #expect(Fmt.stopwatch(0) == "0:00")
    }
}
