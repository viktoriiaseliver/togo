import Testing
import Foundation
@testable import Togo

@Suite("Прогулка и отметки")
@MainActor
struct WalkSessionTests {
    private func сессия(_ kind: ActiveSession.Kind = .walk) -> ActiveSession {
        ActiveSession(kind: kind, startedAt: Date().addingTimeInterval(-600), startedBy: "Виктория")
    }

    @Test("Время считается от начала, а не тикающим счётчиком")
    func durationFromStart() {
        let начало = Date().addingTimeInterval(-1800)
        let session = ActiveSession(kind: .walk, startedAt: начало, startedBy: "Виктория")
        // Телефон можно убрать в карман: секунды не собьются.
        #expect(abs(session.duration() - 1800) < 2)
        #expect(session.duration(at: начало) == 0)
    }

    @Test("Отметок может быть сколько угодно за прогулку")
    func repeatableMarks() {
        var session = сессия()
        for _ in 0..<3 { session.marks.append(.init(kind: .urine)) }
        session.marks.append(.init(kind: .stool))

        #expect(session.count(of: .urine) == 3)
        #expect(session.count(of: .stool) == 1)
        #expect(session.count(of: .water) == 0)
    }

    @Test("Сводка читается человеком")
    func tallyReadable() {
        var session = сессия()
        session.marks.append(.init(kind: .urine))
        session.marks.append(.init(kind: .urine))
        session.marks.append(.init(kind: .stool))

        #expect(session.tally == "пописал ×2 · стул")
    }

    @Test("Пустая прогулка так и говорит")
    func emptyTally() {
        #expect(сессия().tally == "пока ничего не отмечено")
    }

    @Test("Результат выхода выводится из отметок, а не спрашивается заново")
    func outcomeFromMarks() {
        var session = сессия(.outing)
        #expect(session.outcome == nil, "ничего не отмечено — результата нет")

        session.marks.append(.init(kind: .urine))
        #expect(session.outcome == .urine)

        session.marks.append(.init(kind: .stool))
        #expect(session.outcome == .both)

        var пустая = сессия(.outing)
        пустая.marks.append(.init(kind: .note))
        #expect(пустая.outcome == OutingOutcome.none, "вышли, но не сходил")
    }

    @Test("Последнюю отметку можно снять: промахнуться одной рукой легко")
    func undoLastMark() {
        let state = AppState()
        state.startWalk(by: "Виктория")
        state.mark(.urine)
        state.mark(.stool)

        let снятая = state.undoLastMark()
        #expect(снятая?.kind == .stool)
        #expect(state.session?.marks.count == 1)

        state.undoLastMark()
        #expect(state.session?.marks.isEmpty == true)
        #expect(state.undoLastMark() == nil, "снимать нечего — и это не ошибка")
    }

    @Test("Выход и прогулка — разные режимы, но одновременно идёт что-то одно")
    func oneSessionAtATime() {
        let state = AppState()
        state.startOuting(by: "Виктория")
        #expect(state.session?.kind == .outing)
        #expect(!state.isWalking)

        state.startWalk(by: "Тео")
        #expect(state.session?.kind == .walk)
        #expect(state.isWalking)
        #expect(state.session?.startedBy == "Тео")
    }

    @Test("Завершение отдаёт сессию и очищает состояние")
    func finishReturnsSession() {
        let state = AppState()
        state.startWalk(by: "Виктория")
        state.mark(.urine)

        let finished = state.finishSession()
        #expect(finished?.marks.count == 1)
        #expect(state.session == nil)
        #expect(state.finishSession() == nil)
    }

    @Test("Каждая отметка знает, какой записью станет в ленте")
    func marksMapToLog() {
        #expect(ActiveSession.Mark.Kind.urine.logKind == .outing)
        #expect(ActiveSession.Mark.Kind.stool.logKind == .stool)
        #expect(ActiveSession.Mark.Kind.incident.logKind == .incident)
    }
}

@Suite("Возраст и документы")
@MainActor
struct DogProfileTests {
    private func собака(месяцев: Int) -> Dog {
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.birthDate = Calendar.current.date(byAdding: .month, value: -месяцев, to: .now)
        return dog
    }

    @Test("Возраст читается по-русски")
    func ageDescription() {
        #expect(собака(месяцев: 5).ageDescription == "5 месяцев")
        #expect(собака(месяцев: 12).ageDescription == "1 год")
        #expect(собака(месяцев: 26).ageDescription == "2 года 2 месяца")
    }

    @Test("Щенок, взрослая и пожилая — разные режимы")
    func lifeStages() {
        #expect(собака(месяцев: 6).lifeStage == .puppy)
        #expect(собака(месяцев: 24).lifeStage == .adult)
        #expect(собака(месяцев: 96).lifeStage == .senior)
        #expect(Dog(name: "Без даты", weightKg: 4).lifeStage == nil)
    }

    @Test("Опасное разделено по срочности, а не свалено в кучу")
    func toxicList() {
        let сейчас = ToxicItem.common.filter { $0.urgency == .callNow }
        #expect(сейчас.contains { $0.name == "Ксилит" })
        #expect(сейчас.contains { $0.name == "Шоколад" })
        #expect(ToxicItem.common.allSatisfy { !$0.detail.isEmpty })
        #expect(ToxicItem.common.count <= 12, "длинный список в панике никто не дочитает")
    }
}
