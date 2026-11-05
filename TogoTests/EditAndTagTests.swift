import Testing
import Foundation
import SwiftData
@testable import Togo

/// Правка записи и след удаления.
///
/// В живом дневнике 27 августа видно, как человек дважды за день
/// обходил отсутствие правки: записывал 65 г, хотел 75, не находил где
/// поменять — и удалял запись, чтобы создать новую. В базе от этого
/// осталось четыре записи еды вместо двух.
@Suite("Правка и след удаления")
@MainActor
struct EditTraceTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    private func meal(_ grams: Int, at date: Date, dog: Dog, context: ModelContext) -> LogEvent {
        let event = LogEvent(kind: .meal, date: date, authorName: "Вика")
        event.grams = grams
        event.dog = dog
        context.insert(event)
        return event
    }

    @Test("Удалённая запись пропадает из ленты вместе с отменой")
    func traceDiesWithUndo() throws {
        let (context, dog) = try setup()
        let now = Date()
        let event = meal(65, at: now, dog: dog, context: context)
        event.deletedAt = now
        try context.save()

        // Пока тост висит, строка стоит зачёркнутой.
        #expect(Diary.onDayWithTraces(dog.events, now, tracing: [event.id]).count == 1)
        // Тост уехал — ушла и строка.
        #expect(Diary.onDayWithTraces(dog.events, now, tracing: []).isEmpty)
    }

    @Test("Живые записи от следа не зависят")
    func liveEventsAlwaysShown() throws {
        let (context, dog) = try setup()
        let now = Date()
        _ = meal(75, at: now, dog: dog, context: context)
        try context.save()

        #expect(Diary.onDayWithTraces(dog.events, now, tracing: []).count == 1)
    }

    @Test("Поправленные граммы — это одна запись, а не две")
    func editingKeepsOneEvent() throws {
        let (context, dog) = try setup()
        let now = Date()
        let event = meal(65, at: now, dog: dog, context: context)
        try context.save()

        // Ровно то, что делает шаговик в шторке правки.
        event.grams = 75
        try context.save()

        let day = Diary.onDay(dog.events, now)
        #expect(day.count == 1, "обход через «удалить и записать заново» оставлял в базе две")
        #expect(day.first?.grams == 75)
    }
}

/// Прогулка по метке у двери.
@Suite("Метка у двери")
@MainActor
struct WalkTagTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Того", weightKg: 12)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    /// Короткий выход, законченный меткой, «Домой» или из режима
    /// прогулки, ложился в дневник выходом И прогулкой (29.10.2026):
    /// запись выхода заводится в начале, а конец писал `.walk` поверх.
    @Test("Короткий выход закрывается своей записью, а не второй прогулкой")
    func outingClosesAsOneRecord() throws {
        let (context, dog) = try setup()
        let started = Date().addingTimeInterval(-4 * 60)
        let выход = LogEvent(kind: .outing, date: started, authorName: "Вика")
        выход.dog = dog
        context.insert(выход)
        try context.save()

        var session = ActiveSession(kind: .outing, startedAt: started.addingTimeInterval(2),
                                    startedBy: "Вика")
        session.marks = [.init(kind: .urine, at: started.addingTimeInterval(60))]
        #expect(OutingFinisher.close(session, dog: dog, at: Date(), context: context))

        let записи = Diary.active(dog.events)
        #expect(записи.filter { $0.kind == .walk }.isEmpty, "поверх выхода легла прогулка")
        #expect(записи.filter { $0.kind == .outing }.count == 1, "выход задвоился")
        #expect(выход.outcome == .urine, "отметка с блокировки не дошла до результата выхода")
        let минуты = (выход.durationSeconds ?? 0) / 60
        #expect(минуты >= 3 && минуты <= 4)
    }

    @Test("Прогулка записывается со своей длительностью")
    func walkIsRecorded() throws {
        let (context, dog) = try setup()
        let started = Date().addingTimeInterval(-30 * 60)
        let session = ActiveSession(kind: .walk, startedAt: started, startedBy: "Вика")

        // Запись теперь может и не состояться — хранилище отвечает.
        // В тесте это `#require`: не записалось значит тест упал,
        // а не «прошёл с пустым результатом».
        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Вика", context: context))

        #expect(walk.kind == .walk)
        #expect(walk.date == started)
        let minutes = (walk.durationSeconds ?? 0) / 60
        #expect(minutes >= 29 && minutes <= 30)
    }

    @Test("Отметки прогулки становятся записями и знают свою прогулку")
    func marksBecomeEvents() throws {
        let (context, dog) = try setup()
        let started = Date().addingTimeInterval(-20 * 60)
        var session = ActiveSession(kind: .walk, startedAt: started, startedBy: "Вика")
        session.marks = [
            .init(kind: .urine, at: started.addingTimeInterval(120)),
            .init(kind: .stool, at: started.addingTimeInterval(300)),
        ]

        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Вика", context: context))
        let walkID = walk.id
        let marks = dog.events.filter { $0.walkEventID == walkID }
        #expect(marks.count == 2)
        #expect(marks.contains { $0.kind == .outing && $0.outcome == .urine })
        #expect(marks.allSatisfy { $0.note == "на прогулке" })
    }

    @Test("Лакомство с прогулки попадает в подсчёт питания")
    func treatCountsTowardsPortion() throws {
        let (context, dog) = try setup()
        dog.trainingFoodFromPortion = true
        var session = ActiveSession(kind: .walk, startedAt: Date().addingTimeInterval(-600),
                                    startedBy: "Вика")
        session.marks = [.init(kind: .treat, at: Date().addingTimeInterval(-300))]

        _ = WalkRecorder.record(session, dog: dog, author: "Вика", context: context)

        let treat = try #require(dog.events.first { $0.kind == .treat })
        #expect(treat.grams == 5)
        #expect(treat.fromPortion, "иначе пять граммов исчезали из дневной нормы")
    }

    @Test("Прогулка без отметок записывается без хвоста")
    func emptyWalkHasNoTally() throws {
        let (context, dog) = try setup()
        let session = ActiveSession(kind: .walk, startedAt: Date().addingTimeInterval(-900),
                                    startedBy: "Вика")

        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Вика", context: context))
        #expect(walk.note == nil)
    }

    @Test("Пауза не попадает в длительность")
    func pauseIsNotCounted() throws {
        let (context, dog) = try setup()
        let started = Date().addingTimeInterval(-30 * 60)
        var session = ActiveSession(kind: .walk, startedAt: started, startedBy: "Вика")
        session.pausedTotal = 10 * 60

        let walk = try #require(WalkRecorder.record(session, dog: dog,
                                                    author: "Вика", context: context))
        let minutes = (walk.durationSeconds ?? 0) / 60
        #expect(minutes >= 19 && minutes <= 20)
    }
}
