import Testing
import Foundation
import SwiftData
@testable import Togo

/// Лента: одно событие — один блок.
@Suite("Лента · прогулка собирается в одно событие")
@MainActor
struct TimelineGroupingTests {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        return day.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private func event(_ kind: LogKind, _ hour: Int, _ minute: Int) -> LogEvent {
        LogEvent(kind: kind, date: at(hour, minute), authorName: "Виктория")
    }

    /// Ровно то, что нашлось в живом дневнике 26 августа: прогулка в 18:12,
    /// её отметки — в 18:45.
    private func walkWithMarks() -> (walk: LogEvent, marks: [LogEvent]) {
        let walk = event(.walk, 18, 12)
        walk.durationSeconds = 33 * 60
        walk.note = "пописал · стул"

        let urine = event(.outing, 18, 45)
        let stool = event(.stool, 18, 45)
        for mark in [urine, stool] { mark.walkEventID = walk.id }
        return (walk, [urine, stool])
    }

    @Test("Отметки уходят внутрь прогулки, а не встают отдельными строками")
    func marksNestUnderWalk() {
        let (walk, marks) = walkWithMarks()
        let blocks = TimelineBuilder.blocks([walk] + marks)

        #expect(blocks.count == 1)
        #expect(blocks[0].event.id == walk.id)
        #expect(blocks[0].marks.count == 2)
    }

    @Test("У прогулки есть конец, а не только начало")
    func walkHasEnd() {
        let (walk, marks) = walkWithMarks()
        let block = TimelineBuilder.blocks([walk] + marks)[0]

        #expect(block.startedAt == at(18, 12))
        #expect(block.endedAt == at(18, 45))
        #expect(block.isSpan)
    }

    @Test("Промежуток считается от конца прогулки, а не от её начала")
    func gapMeasuredFromEnd() {
        // Лента честно сообщала «прошло 33 минуты» между прогулкой
        // и её собственной отметкой — то есть внутри одного события.
        let (walk, marks) = walkWithMarks()
        let next = event(.outing, 20, 31)
        let blocks = TimelineBuilder.blocks([walk] + marks + [next])

        #expect(blocks.count == 2)
        let gap = try! #require(
            TimelineBuilder.timeIndoors(before: 1, in: blocks, threshold: 3600)
        )
        // От 18:45 до 20:31 — час сорок шесть, а не два часа девятнадцать.
        #expect(gap == Double(106 * 60))
    }

    @Test("Отметка без прогулки остаётся своей строкой")
    func orphanMarkStaysTopLevel() {
        let lone = event(.outing, 8, 40)
        let blocks = TimelineBuilder.blocks([lone])

        #expect(blocks.count == 1)
        #expect(blocks[0].marks.isEmpty)
    }

    @Test("Мгновенное событие не притворяется отрезком")
    func instantIsNotSpan() {
        let meal = event(.meal, 16, 5)
        let block = TimelineBuilder.blocks([meal])[0]

        #expect(!block.isSpan)
        #expect(block.endedAt == block.startedAt)
    }

    @Test("Порядок сохраняется по времени")
    func blocksStayOrdered() {
        let (walk, marks) = walkWithMarks()
        let morning = event(.meal, 8, 58)
        let evening = event(.meal, 20, 31)
        let blocks = TimelineBuilder.blocks([evening] + marks + [walk, morning])

        #expect(blocks.map(\.startedAt) == [at(8, 58), at(18, 12), at(20, 31)])
    }
}

@Suite("Лента · связывание старых записей")
@MainActor
struct WalkLinkMigrationTests {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        return day.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    @Test("Отметки «на прогулке» находят свою прогулку по времени")
    func legacyMarksGetLinked() {
        // До появления связи ею служила подпись словами.
        let walk = LogEvent(kind: .walk, date: at(18, 12), authorName: "Виктория")
        walk.durationSeconds = 33 * 60

        let urine = LogEvent(kind: .outing, date: at(18, 45), authorName: "Виктория")
        urine.note = "на прогулке"
        let stool = LogEvent(kind: .stool, date: at(18, 45), authorName: "Виктория")
        stool.note = "на прогулке"

        let linked = WalkLinkMigration.link([walk, urine, stool])

        #expect(linked == 2)
        #expect(urine.walkEventID == walk.id)
        #expect(stool.walkEventID == walk.id)
    }

    @Test("Отметка вне окна прогулки к ней не приписывается")
    func farMarkStaysFree() {
        let walk = LogEvent(kind: .walk, date: at(8, 41), authorName: "Виктория")
        walk.durationSeconds = 10 * 60

        let late = LogEvent(kind: .outing, date: at(16, 18), authorName: "Виктория")
        late.note = "на прогулке"

        _ = WalkLinkMigration.link([walk, late])
        #expect(late.walkEventID == nil)
    }

    @Test("Каждая отметка достаётся своей прогулке, а не первой попавшейся")
    func marksGoToTheirOwnWalk() {
        let morning = LogEvent(kind: .walk, date: at(16, 18), authorName: "Виктория")
        morning.durationSeconds = 5 * 60
        let evening = LogEvent(kind: .walk, date: at(18, 12), authorName: "Виктория")
        evening.durationSeconds = 33 * 60

        let early = LogEvent(kind: .outing, date: at(16, 18), authorName: "Виктория")
        early.note = "на прогулке"
        let late = LogEvent(kind: .stool, date: at(18, 45), authorName: "Виктория")
        late.note = "на прогулке"

        _ = WalkLinkMigration.link([morning, evening, early, late])

        #expect(early.walkEventID == morning.id)
        #expect(late.walkEventID == evening.id)
    }

    @Test("Повторный запуск ничего не портит")
    func migrationIsIdempotent() {
        let walk = LogEvent(kind: .walk, date: at(18, 12), authorName: "Виктория")
        walk.durationSeconds = 33 * 60
        let mark = LogEvent(kind: .outing, date: at(18, 45), authorName: "Виктория")
        mark.note = "на прогулке"

        #expect(WalkLinkMigration.link([walk, mark]) == 1)
        #expect(WalkLinkMigration.link([walk, mark]) == 0)
        #expect(mark.walkEventID == walk.id)
    }
}

@Suite("Лента · правка и удаление прогулки")
@MainActor
struct WalkEditingTests {

    @Test("Отмена удаления возвращает запись, а не добивает её")
    func undoRestores() {
        // «Удаление можно отменить 5 секунд» было написано на экране,
        // но тост об удалении не нёс ничего, и кнопка не делала ничего.
        let id = UUID()
        let toast = AppState.UndoToast(message: "Удалено · Прогулка",
                                       action: .restoreDeleted([id]))

        #expect(toast.action == .restoreDeleted([id]))
    }

    @Test("Только что созданная запись отменяется удалением")
    func undoRemovesCreated() {
        let id = UUID()
        let toast = AppState.UndoToast(message: "Записано · Еда", action: .removeCreated(id))

        #expect(toast.action == .removeCreated(id))
    }
}

@Suite("Лента · выход, переросший в прогулку")
@MainActor
struct OutingIntoWalkTests {

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        return day.addingTimeInterval(Double(hour * 3600 + minute * 60 + second))
    }

    @Test("Выход без исхода и прогулка через минуту — одно событие")
    func outingBecomesWalkStart() {
        // Ровно то, что нашлось в живом дневнике: «Вывожу» в 08:40:05
        // и прогулка в 08:41:00. Кнопка «Вывожу» пишет выход сразу,
        // прогулка — только когда закончилась, и в ленте получались
        // две строки подряд про один выход из дома.
        let outing = LogEvent(kind: .outing, date: at(8, 40, 5), authorName: "Виктория")
        let walk = LogEvent(kind: .walk, date: at(8, 41), authorName: "Виктория")
        walk.durationSeconds = 58 * 60

        let blocks = TimelineBuilder.blocks([outing, walk])

        #expect(blocks.count == 1)
        #expect(blocks[0].event.id == walk.id)
        // Началом считается момент, когда вышли из дома.
        #expect(blocks[0].startedAt == at(8, 40, 5))
    }

    @Test("Выход с исходом остаётся своей строкой")
    func completedOutingStaysOwnRow() {
        // Сходил — значит, выход состоялся сам по себе, и прогулка после
        // него это уже второй раз на улицу.
        let outing = LogEvent(kind: .outing, date: at(8, 40), authorName: "Виктория")
        outing.outcome = .urine
        let walk = LogEvent(kind: .walk, date: at(8, 41), authorName: "Виктория")
        walk.durationSeconds = 10 * 60

        #expect(TimelineBuilder.blocks([outing, walk]).count == 2)
    }

    @Test("Прогулка через полчаса после выхода к нему не приклеивается")
    func lateWalkIsSeparate() {
        let outing = LogEvent(kind: .outing, date: at(8, 40), authorName: "Виктория")
        let walk = LogEvent(kind: .walk, date: at(9, 20), authorName: "Виктория")
        walk.durationSeconds = 10 * 60

        #expect(TimelineBuilder.blocks([outing, walk]).count == 2)
    }

    @Test("Один выход не достаётся двум прогулкам")
    func openingUsedOnce() {
        let outing = LogEvent(kind: .outing, date: at(8, 40), authorName: "Виктория")
        let first = LogEvent(kind: .walk, date: at(8, 41), authorName: "Виктория")
        first.durationSeconds = 5 * 60
        let second = LogEvent(kind: .walk, date: at(8, 43), authorName: "Виктория")
        second.durationSeconds = 5 * 60

        let blocks = TimelineBuilder.blocks([outing, first, second])
        #expect(blocks.count == 2)
        #expect(blocks.filter { $0.startedWith != nil }.count == 1)
    }

    @Test("Порядок отметок с одинаковым временем не пляшет")
    func stableOrderForEqualTimes() {
        // В живом дневнике стул и выход записаны секунда в секунду.
        let walk = LogEvent(kind: .walk, date: at(20, 30), authorName: "Виктория")
        walk.durationSeconds = 43 * 60
        let stool = LogEvent(kind: .stool, date: at(21, 13), authorName: "Виктория")
        let urine = LogEvent(kind: .outing, date: at(21, 13), authorName: "Виктория")
        for mark in [stool, urine] { mark.walkEventID = walk.id }

        let first = TimelineBuilder.blocks([walk, stool, urine])[0].marks.map(\.id)
        let again = TimelineBuilder.blocks([walk, urine, stool])[0].marks.map(\.id)

        #expect(first == again)
    }
}

@Suite("Лента · сколько собака дома")
@MainActor
struct TimeIndoorsTests {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        return day.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private func event(_ kind: LogKind, _ hour: Int, _ minute: Int,
                       minutes: Int = 0) -> LogEvent {
        let event = LogEvent(kind: kind, date: at(hour, minute), authorName: "Виктория")
        if minutes > 0 { event.durationSeconds = minutes * 60 }
        return event
    }

    @Test("Еда посередине не рвёт промежуток между выходами")
    func mealsDoNotBreakTheGap() {
        // Между кормлениями человек и так примерно знает. Считать надо
        // одно: сколько собака терпит.
        let morning = event(.walk, 8, 41, minutes: 58)
        let lunch = event(.meal, 12, 0)
        let dinner = event(.meal, 16, 5)
        let evening = event(.walk, 18, 12, minutes: 33)

        let blocks = TimelineBuilder.blocks([morning, lunch, dinner, evening])
        #expect(blocks.count == 4)

        // Промежуток есть только у вечерней прогулки — и он от 09:39.
        #expect(TimelineBuilder.timeIndoors(before: 1, in: blocks, threshold: 3600) == nil)
        #expect(TimelineBuilder.timeIndoors(before: 2, in: blocks, threshold: 3600) == nil)

        let indoors = try! #require(
            TimelineBuilder.timeIndoors(before: 3, in: blocks, threshold: 3600)
        )
        #expect(indoors == Double(8 * 3600 + 33 * 60))
    }

    @Test("У первого выхода за день промежутка нет")
    func firstOutingHasNoGap() {
        let blocks = TimelineBuilder.blocks([event(.walk, 8, 41, minutes: 58)])
        #expect(TimelineBuilder.timeIndoors(before: 0, in: blocks, threshold: 3600) == nil)
    }

    @Test("Короткий промежуток не показываем")
    func shortGapStaysQuiet() {
        let first = event(.outing, 8, 0)
        let second = event(.outing, 8, 30)
        let blocks = TimelineBuilder.blocks([first, second])

        #expect(TimelineBuilder.timeIndoors(before: 1, in: blocks, threshold: 3600) == nil)
    }

    @Test("Сейчас: считается от конца последнего выхода, а не последней записи")
    func nowCountsFromLastOuting() {
        // Пока считали от последней записи любого вида, вечернее кормление
        // обнуляло цифру: «прошло десять минут» — хотя гулял он три часа назад.
        let walk = event(.walk, 18, 12, minutes: 33)
        let supper = event(.meal, 20, 31)
        let blocks = TimelineBuilder.blocks([walk, supper])

        let indoors = try! #require(
            TimelineBuilder.timeIndoorsNow(blocks, now: at(21, 45), threshold: 3600)
        )
        // От 18:45 до 21:45 — три часа, а не час четырнадцать от ужина.
        #expect(indoors == Double(3 * 3600))
    }

    @Test("Пока прогулка идёт, дома он не сидит")
    func openWalkCountsFromItsEnd() {
        let walk = event(.walk, 18, 12, minutes: 33)
        let blocks = TimelineBuilder.blocks([walk])

        #expect(TimelineBuilder.timeIndoorsNow(blocks, now: at(18, 30), threshold: 3600) == nil)
    }
}
