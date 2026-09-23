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
        let state = AppState.наСвоёмТелефоне()
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
        let state = AppState.наСвоёмТелефоне()
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
        let state = AppState.наСвоёмТелефоне()
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

/// Прогулка сбрасывалась, и приходилось начинать новую. Причина: сессия
/// жила только в памяти, а телефон полчаса лежит в кармане — система вправе
/// выгрузить приложение в любой момент.
@Suite("Прогулка переживает закрытие приложения")
@MainActor
struct SessionPersistenceTests {
    private func чистое() {
        ActiveSessionStore.save(nil)
    }

    @Test("Прогулка возвращается после перезапуска")
    func sessionSurvivesRelaunch() {
        чистое()
        let начало = Date().addingTimeInterval(-900)

        // Первый запуск: пошли гулять и отметили пару вещей.
        let первый = AppState.наСвоёмТелефоне()
        первый.startWalk(by: "Виктория", at: начало)
        первый.mark(.urine)
        первый.mark(.reaction)

        // Приложение выгрузили. Второй запуск — новое состояние.
        let второй = AppState.наСвоёмТелефоне()

        #expect(второй.session != nil, "прогулка не должна пропадать")
        #expect(второй.session?.startedAt == начало, "и таймер продолжается с того же места")
        #expect(второй.session?.marks.count == 2, "отметки тоже на месте")
        #expect(второй.session?.reactions == 1)
        чистое()
    }

    @Test("Завершённая прогулка не воскресает")
    func finishedSessionDoesNotReturn() {
        чистое()
        let первый = AppState.наСвоёмТелефоне()
        первый.startWalk(by: "Виктория")
        первый.finishSession()

        #expect(AppState.наСвоёмТелефоне().session == nil)
        чистое()
    }

    @Test("Забытую прогулку через сутки не показываем")
    func staleSessionIsDropped() {
        чистое()
        let давно = Date().addingTimeInterval(-20 * 3600)
        ActiveSessionStore.save(
            ActiveSession(kind: .walk, startedAt: давно, startedBy: "Виктория")
        )

        #expect(ActiveSessionStore.load() == nil,
                "таймер на двадцать часов хуже, чем никакого")
        #expect(AppState.наСвоёмТелефоне().session == nil)
        чистое()
    }

    @Test("Пауза тоже переживает перезапуск")
    func pauseSurvives() {
        чистое()
        let первый = AppState.наСвоёмТелефоне()
        первый.startWalk(by: "Виктория", at: Date().addingTimeInterval(-600))
        первый.pauseSession()

        let второй = AppState.наСвоёмТелефоне()
        #expect(второй.session?.isPaused == true)
        чистое()
    }
}

@Suite("Срывы на прогулке")
@MainActor
struct ReactionTests {
    @Test("Срывов может быть несколько за выход — считается количество")
    func reactionsAreCounted() {
        var session = ActiveSession(kind: .walk, startedAt: Date(), startedBy: "Виктория")
        for _ in 0..<4 { session.marks.append(.init(kind: .reaction)) }

        #expect(session.reactions == 4)
        #expect(session.tally.contains("сорвался ×4"))
        #expect(ActiveSession.Mark.Kind.reaction.isRepeatable)
    }

    @Test("Срыв становится своей записью в ленте, а не инцидентом")
    func reactionMapsToOwnKind() {
        #expect(ActiveSession.Mark.Kind.reaction.logKind == .reaction)
        #expect(LogKind.reaction.title == "Срыв")
    }

    @Test("У срыва есть на что и как близко")
    func reactionDetails() {
        let event = LogEvent(kind: .reaction, authorName: "Виктория")
        event.reactionTrigger = .dog
        event.reactionDistance = .close

        #expect(event.subtitle?.contains("другая собака") == true)
        #expect(event.subtitle?.contains("вплотную") == true)
    }

    @Test("Срыв не поднимает запись в терракот: это порог, а не кровь")
    func reactionIsNotAlarm() {
        let event = LogEvent(kind: .reaction, authorName: "Виктория")
        event.reactionTrigger = .dog
        #expect(!event.raisesAlarm)
    }

    @Test("Срыв бывает и не на прогулке — тогда это инцидент")
    func reactionAsIncident() {
        #expect(IncidentKind.reaction.asksReactionDetails)
        #expect(!IncidentKind.vomit.asksReactionDetails)
        #expect(!IncidentKind.reaction.showsPunishmentWarning,
                "строка про наказание — про лужу, у срыва свой текст")
    }

    @Test("В истории срывы — отдельный фильтр")
    func reactionsHaveTheirOwnFilter() {
        let срыв = LogEvent(kind: .reaction, authorName: "Виктория")
        let рвота = LogEvent(kind: .incident, authorName: "Виктория")
        рвота.incidentKind = .vomit

        #expect(HistoryFilter.reactions.matches(срыв))
        #expect(!HistoryFilter.reactions.matches(рвота))
        #expect(HistoryFilter.reactions.title == "Срывы")
    }
}
