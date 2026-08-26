import Testing
import Foundation
import SwiftData
@testable import Togo

/// Системы, которые были написаны и не вызывались ниоткуда.
///
/// Отдельный набор, потому что это особый сорт ошибки: код есть, экраны
/// есть, тесты на сам код проходят — а в живом приложении не срабатывает
/// ничего. Ловится только вопросом «кто это вызывает».
@Suite("Непокрытая логика")
@MainActor
struct DeadLogicTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    // MARK: Утренний бриф

    @Test("В бриф попадают дела на завтра, а не пустота")
    func briefHasLines() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = Calendar.current.date(byAdding: .day, value: -21, to: .now)
        когти.dog = dog
        context.insert(когти)

        let строки = ReminderScheduler.briefLines(dog: dog)
        #expect(строки.count == 1)
        #expect(строки[0].contains("Когти"))
    }

    @Test("Отложенное дважды подсвечивается в брифе, но не становится тревогой")
    func snoozedIsMarked() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        let дело = CareTask(title: "Купать", detail: "", kind: .periodic, intervalDays: 60)
        дело.lastDone = Calendar.current.date(byAdding: .day, value: -60, to: .now)
        дело.snoozeCount = 2
        дело.dog = dog
        context.insert(дело)

        #expect(ReminderScheduler.briefLines(dog: dog)[0].contains("откладывали"))
    }

    @Test("Ежедневное в бриф не сыплется каждый день без причины")
    func briefIsShort() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        for index in 0..<9 {
            let дело = CareTask(title: "Дело \(index)", detail: "", kind: .periodic, intervalDays: 7)
            дело.lastDone = Calendar.current.date(byAdding: .day, value: -8, to: .now)
            дело.dog = dog
            context.insert(дело)
        }

        #expect(ReminderScheduler.briefLines(dog: dog).count <= 4,
                "один пуш, а не список из девяти строк")
    }

    @Test("Без собаки бриф пустой и ничего не шлёт")
    func briefWithoutDog() {
        #expect(ReminderScheduler.briefLines(dog: nil).isEmpty)
    }

    // MARK: Как попросил

    @Test("Лай, вытесняющий спокойный сигнал, виден в цифрах")
    func barkingIsDetected() {
        var события: [LogEvent] = []
        let сейчас = Date()

        // Две недели назад просил спокойно.
        for index in 0..<9 {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(9 + index) * 24 * 3600),
                                 authorName: "Виктория")
            выход.askSignal = .satAtDoor
            события.append(выход)
        }
        // На этой неделе в основном лает.
        for index in 0..<9 {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(index) * 8 * 3600),
                                 authorName: "Виктория")
            выход.askSignal = index < 7 ? .barked : .satAtDoor
            события.append(выход)
        }

        #expect(Diary.barkingIsDisplacingCalm(события, now: сейчас),
                "ровно тот случай, ради которого этот вопрос и задаётся")
    }

    @Test("Пока сигналов мало, выводов не делаем")
    func fewSignalsMeanSilence() {
        let сейчас = Date()
        let выход = LogEvent(kind: .outing, date: сейчас, authorName: "Виктория")
        выход.askSignal = .barked

        #expect(!Diary.barkingIsDisplacingCalm([выход], now: сейчас))
    }

    @Test("Спокойные и беспокойные сигналы считаются раздельно")
    func tallySplitsSignals() {
        let сейчас = Date()
        var события: [LogEvent] = []
        for (index, сигнал) in [AskSignal.satAtDoor, .cameAndLooked, .barked, .scratchedDoor].enumerated() {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(index) * 3600),
                                 authorName: "Виктория")
            выход.askSignal = сигнал
            события.append(выход)
        }

        let счёт = Diary.signalTally(события, from: сейчас.addingTimeInterval(-24 * 3600), to: сейчас.addingTimeInterval(1))
        #expect(счёт.calm == 2)
        #expect(счёт.barking == 2)
        #expect(счёт.total == 4)
    }

    // MARK: Шаги обучения

    @Test("Шаг закрывается после двух удачных занятий подряд")
    func stepClosesAfterTwoGood() {
        let шаг = TrainingStep(cue: "Ко мне", place: "Дома", person: "Виктория", distanceMeters: 2)
        #expect(!шаг.isClosed)
        шаг.consecutiveGoodSessions = 2
        #expect(шаг.isClosed)
    }

    @Test("Занятие с отказом от еды прогресс не двигает")
    func refusedFoodVoidsProgress() {
        let занятие = TrainingSession(cue: "Ко мне", place: "Дома",
                                      person: "Виктория", distanceMeters: 2)
        занятие.attempts = 5
        занятие.successes = 5
        занятие.observations = [.refusedFood]

        #expect(занятие.isVoided)
        #expect(занятие.isGoodSession, "само по себе занятие удачное")
        // Но экран не засчитает его в прогресс: countsTowardProgress
        // выставляется по наблюдениям и времени.
    }

    // MARK: Беру на себя

    @Test("«Беру на себя» живёт 45 минут и не даёт дать дозу дважды")
    func claimProtectsFromDoubleDose() {
        let доза = DoseRecord(scheduledAt: Date())
        let взяли = Date()
        доза.claimedBy = "Тео"
        доза.claimedAt = взяли

        #expect(доза.claimIsActive(at: взяли.addingTimeInterval(40 * 60)))
        #expect(!доза.claimIsActive(at: взяли.addingTimeInterval(46 * 60)),
                "срок истёк — эскалация идёт дальше")
    }

    @Test("Эскалация не трогает того, кто уже отметил")
    func givenDoseIsQuiet() {
        let время = Date()
        let доза = DoseRecord(scheduledAt: время)
        доза.givenAt = время
        #expect(доза.escalationStage(at: время.addingTimeInterval(2 * 3600)) == 0)
    }
}
