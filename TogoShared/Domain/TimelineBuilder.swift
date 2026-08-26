import Foundation

/// Как лента складывается из записей.
///
/// Запись в базе и строка в ленте — не одно и то же. Прогулка в базе это
/// одна запись о самой прогулке плюс по записи на каждую отметку; в голове
/// человека это **одно событие**, у которого есть начало, конец и то, что
/// в нём произошло.
///
/// Пока лента показывала записи как есть, получалось так: прогулка стояла
/// в момент выхода, её отметки — в момент возвращения, между ними полчаса
/// и чужие строки, а итог прогулки был написан дважды — подписью к ней
/// и теми же отметками отдельно. Понять, что это одно событие, можно было
/// только сопоставив времена в уме.
struct TimelineBlock: Identifiable {
    /// Главная запись: то, что человек назовёт этим событием.
    let event: LogEvent
    /// Выход, с которого всё началось, если он перерос в прогулку.
    let startedWith: LogEvent?
    /// Что произошло внутри. Пусто у всего, кроме прогулок.
    let marks: [LogEvent]

    var id: UUID { event.id }

    /// Начало — по самой ранней записи события. Если «Вывожу» переросло
    /// в прогулку, началом считается момент, когда вышли из дома.
    var startedAt: Date { startedWith?.date ?? event.date }

    /// Когда событие закончилось. Для прогулки — по её длительности,
    /// а если её нет, то по последней отметке.
    var endedAt: Date {
        if let seconds = event.durationSeconds, seconds > 0 {
            return event.date.addingTimeInterval(Double(seconds))
        }
        return max(marks.map(\.date).max() ?? event.date, event.date)
    }

    /// Событие заняло время, а не случилось мгновенно.
    var isSpan: Bool { endedAt.timeIntervalSince(startedAt) >= 60 }

    var hasMarks: Bool { !marks.isEmpty }

    /// Собаку выводили на улицу. Прогулка и выход по нужде — оба.
    var isOuting: Bool { event.kind == .walk || event.kind == .outing }
}

enum TimelineBuilder {
    /// Насколько быстро «Вывожу» может перерасти в прогулку.
    ///
    /// Кнопка «Вывожу» записывает выход сразу, а прогулка — только когда
    /// закончилась. Человек, который вышел по нужде и решил погулять,
    /// получал в ленте две строки подряд про один и тот же выход из дома.
    /// Пять минут — это «ещё не дошли до угла».
    static let outingIntoWalk: TimeInterval = 5 * 60
    /// Собрать ленту: отметки прогулок уходят внутрь своих прогулок.
    ///
    /// Отметка без прогулки остаётся самостоятельной строкой — так бывает
    /// у записей, сделанных до того, как связь появилась, и у всего,
    /// что записано вручную вне прогулки.
    static func blocks(_ events: [LogEvent]) -> [TimelineBlock] {
        // Сортировка с запасным ключом: у отметок одной прогулки время
        // совпадает до секунды, и без него порядок между ними случайный.
        let sorted = events.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
        }
        let walkIDs = Set(sorted.filter { $0.kind == .walk }.map(\.id))

        var marksByWalk: [UUID: [LogEvent]] = [:]
        for event in sorted {
            guard let walkID = event.walkEventID, walkIDs.contains(walkID) else { continue }
            marksByWalk[walkID, default: []].append(event)
        }

        let openings = outingsThatBecameWalks(sorted)

        return sorted.compactMap { event in
            // Отметка, у которой прогулка нашлась, своей строки не получает.
            if let walkID = event.walkEventID, walkIDs.contains(walkID), event.id != walkID {
                return nil
            }
            // Выход, переросший в прогулку, тоже: он стал её началом.
            if openings.values.contains(where: { $0.id == event.id }) { return nil }

            return TimelineBlock(
                event: event,
                startedWith: openings[event.id],
                marks: marksByWalk[event.id]?.sorted { $0.date < $1.date } ?? []
            )
        }
    }

    /// Выход без исхода, за которым сразу пошла прогулка, — это её начало.
    ///
    /// Данные не трогаем: обе записи остаются на месте и правятся по
    /// отдельности. Меняется только то, как лента их показывает.
    private static func outingsThatBecameWalks(_ sorted: [LogEvent]) -> [UUID: LogEvent] {
        var result: [UUID: LogEvent] = [:]
        var taken = Set<UUID>()

        for walk in sorted where walk.kind == .walk {
            let opening = sorted.last { candidate in
                candidate.kind == .outing
                    && candidate.outcome == nil
                    && candidate.walkEventID == nil
                    && !taken.contains(candidate.id)
                    && candidate.date <= walk.date
                    && walk.date.timeIntervalSince(candidate.date) <= outingIntoWalk
            }
            guard let opening else { continue }
            result[walk.id] = opening
            taken.insert(opening.id)
        }
        return result
    }

    /// Сколько прошло с прошлого выхода.
    ///
    /// Промежуток в ленте нужен ровно для одного вопроса: давно ли собака
    /// была на улице. Между кормлениями человек и так примерно знает,
    /// а вот «сколько он уже терпит» — то, что считают по пальцам.
    ///
    /// Поэтому промежуток отмеряется от выхода до выхода и не сбивается
    /// о то, что случилось между ними: еда и вода посередине его не рвут.
    /// Раньше он считался между любыми соседними строками — то есть
    /// и внутри одной прогулки: лента честно сообщала «прошло 33 минуты»
    /// между прогулкой и её собственной отметкой.
    static func timeIndoors(before index: Int, in blocks: [TimelineBlock],
                            threshold: TimeInterval) -> TimeInterval? {
        guard blocks.indices.contains(index), blocks[index].isOuting else { return nil }
        guard let previous = blocks[..<index].last(where: \.isOuting) else { return nil }
        let interval = blocks[index].startedAt.timeIntervalSince(previous.endedAt)
        return interval >= threshold ? interval : nil
    }

    /// Сколько собака дома прямо сейчас — от конца последнего выхода.
    static func timeIndoorsNow(_ blocks: [TimelineBlock], now: Date,
                               threshold: TimeInterval) -> TimeInterval? {
        guard let last = blocks.last(where: \.isOuting) else { return nil }
        let interval = now.timeIntervalSince(last.endedAt)
        return interval >= threshold ? interval : nil
    }
}

/// Разовое связывание отметок с их прогулками у тех, кто гулял
/// до появления связи.
///
/// Связью служила подпись «на прогулке» словами — по ней и восстанавливаем,
/// с проверкой по времени: отметка должна попадать в окно прогулки.
enum WalkLinkMigration {
    /// Запас на случай, если прогулку закончили с задержкой.
    static let slack: TimeInterval = 5 * 60
    static let legacyNote = "на прогулке"

    /// Проставить связи. Возвращает, сколько отметок нашли свою прогулку.
    @discardableResult
    static func link(_ events: [LogEvent]) -> Int {
        let walks = events.filter { $0.kind == .walk && $0.deletedAt == nil }
            .sorted { $0.date < $1.date }
        guard !walks.isEmpty else { return 0 }

        var linked = 0
        for event in events where event.walkEventID == nil && event.note == legacyNote {
            guard let walk = walks.last(where: { walk in
                let start = walk.date.addingTimeInterval(-slack)
                let end = walk.date
                    .addingTimeInterval(Double(walk.durationSeconds ?? 0) + slack)
                return event.date >= start && event.date <= end
            }) else { continue }
            event.walkEventID = walk.id
            linked += 1
        }
        return linked
    }
}
