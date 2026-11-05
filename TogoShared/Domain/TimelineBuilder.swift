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

    /// Когда событие закончилось.
    ///
    /// Берётся позднее из двух: конец по длительности и последняя отметка.
    /// Длительность прогулки считается **без пауз** — постояли у магазина,
    /// и она меньше, чем времени прошло. В живом дневнике нашлась прогулка
    /// на пятнадцать минут, отметки которой стоят через тридцать три:
    /// без этого правила отметка оказывалась позже конца своего же события.
    var endedAt: Date {
        let byDuration = event.date.addingTimeInterval(Double(event.durationSeconds ?? 0))
        return max(byDuration, marks.map(\.date).max() ?? event.date)
    }

    /// Событие заняло время, а не случилось мгновенно.
    var isSpan: Bool { endedAt.timeIntervalSince(startedAt) >= 60 }

    // `hasMarks` стоял здесь и удалён 27.10.2026: ноль читателей,
    // и места, где он нужен, нет.
    //
    // Замер: читатель был один — `DayTimeline.swift:134` в `acb0ecf`,
    // отступ строки (`block.hasMarks ? s4 : s10`), — и исчез вместе
    // с рельсом в `da6e68a` («сплошные строки вместо рельса»). Контроль
    // того же замера: `markGroups` и `isSpan` живы с тех пор и по сей
    // день (DayTimeline.swift:86 и :212/:231; второй контейнер,
    // DayTimelineList.swift, удалён 05.11.2026).
    //
    // Почему не подключаю: отметки рисуются `ForEach(block.markGroups)`
    // в контейнере ленты, а пустой массив даёт ноль строк сам —
    // вопрос «есть ли отметки» там не задаётся по устройству.
    // Прямой читатель `marks` вне тестов был один,
    // `DayTimelineList.swift:144`, и удалён вместе с файлом 05.11.2026.
    // Проверка: `git grep -n "hasMarks"` — ожидается ТОЛЬКО эта запись
    // и ни одной строки кода (ноль он не даст: греп найдёт сам
    // комментарий). Контроль — `git grep -n "markGroups"`, обязан
    // найти оба ряда ленты.

    /// Собаку выводили на улицу. Прогулка и выход по нужде — оба.
    var isOuting: Bool { event.kind == .walk || event.kind == .outing }

    /// Отметки, сведённые по виду.
    ///
    /// Три «пописал» подряд — это не три события, а одно наблюдение
    /// с числом. В живом дневнике внутри одной прогулки на сорок три
    /// минуты стояли отметки в 06:34, 06:38 и 06:39: три почти одинаковых
    /// времени, из которых человек не узнаёт ничего, чего не знал бы
    /// из «пописал ×3».
    var markGroups: [MarkGroup] {
        var order: [LogKind] = []
        var byKind: [LogKind: [LogEvent]] = [:]
        for mark in marks {
            if byKind[mark.kind] == nil { order.append(mark.kind) }
            byKind[mark.kind, default: []].append(mark)
        }
        return order.compactMap { kind in
            guard let events = byKind[kind], let first = events.first else { return nil }
            return MarkGroup(kind: kind, events: events, representative: first)
        }
    }
}

/// Отметки одного вида внутри одной прогулки.
struct MarkGroup: Identifiable {
    let kind: LogKind
    let events: [LogEvent]
    /// Первая по времени — на неё и открывается запись, если она одна.
    let representative: LogEvent

    var id: UUID { representative.id }
    var count: Int { events.count }
    var raisesAlarm: Bool { events.contains(where: \.raisesAlarm) }

    /// Что произошло — своими словами, а не именем вида записи.
    ///
    /// «Пописал», а не «Выход»: внутри прогулки это отметка, и общее
    /// имя вида здесь означало бы совсем другое событие.
    var title: String {
        switch kind {
        case .outing: String(localized: "пописал")
        case .stool: String(localized: "сходил по-большому")
        case .water: String(localized: "попил")
        case .treat: String(localized: "лакомство")
        case .training: String(localized: "занятие")
        case .reaction: String(localized: "сорвался")
        case .incident: String(localized: "инцидент")
        case .note: representative.note ?? String(localized: "заметка")
        default: kind.title.lowercased()
        }
    }

    /// Подробность — только у единственной отметки: у трёх она была бы
    /// от первой попавшейся.
    var detail: String? {
        guard count == 1 else { return nil }
        switch kind {
        case .stool: return representative.stoolForm.map { "· " + $0.title.lowercased() }
        case .reaction:
            return representative.reactionDistance.map { "· " + $0.title.lowercased() }
        default: return nil
        }
    }
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
        // ВТОРАЯ квадратичность той же функции, замер 28.10.2026.
        //
        // Ниже стояло `openings.values.contains(where: { $0.id == … })`
        // — то есть на КАЖДУЮ запись шёл проход по всем найденным
        // началам прогулок. При 2100 записях и 525 прогулках это
        // миллион с лишним сравнений, и именно они остались после
        // починки первой квадратичности:
        //
        // ```
        // blocks до обеих починок   903 мс
        // после первой              477 мс   ← половина цены была ЗДЕСЬ
        // ```
        //
        // > Починив одну квадратичность, легко доложить «ускорено
        // > вдвое» и не заметить вторую в той же функции. Различает
        // > не внимательность, а ПОВТОРНЫЙ ЗАМЕР после починки.
        //
        // Множество строится один раз; проверка становится O(1).
        let началиПрогулку = Set(openings.values.map(\.id))

        return sorted.compactMap { event in
            // Отметка, у которой прогулка нашлась, своей строки не получает.
            if let walkID = event.walkEventID, walkIDs.contains(walkID), event.id != walkID {
                return nil
            }
            // Выход, переросший в прогулку, тоже: он стал её началом.
            if началиПрогулку.contains(event.id) { return nil }

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
        // # ЗДЕСЬ БЫЛА ГЛАВНАЯ ПРИЧИНА ТОРМОЗОВ ПРОКРУТКИ
        //
        // Прежняя редакция звала `sorted.last { … }` НА КАЖДУЮ
        // прогулку, то есть проходила весь дневник заново столько раз,
        // сколько в нём прогулок. Замер 28.10.2026 на 1400 записях
        // с прогулками:
        //
        // ```
        // TimelineBuilder.blocks   903 мс   ← один проход
        // бюджет кадра при 60 к/с   16 мс
        // ```
        //
        // Девятьсот миллисекунд на построение ленты — это и есть
        // «скролл тормозит»: `body` зовёт его на каждый кадр.
        //
        // > **Прежний замер показывал семь миллисекунд и был честен:**
        // > в его данных не было ни одной прогулки, и этот цикл
        // > не выполнялся ни разу. Замер на данных без предмета даёт
        // > верное число и ложный вывод.
        //
        // Окно поиска — пять минут (`outingIntoWalk`), то есть
        // кандидатов в нём единицы, а искали по всему массиву.
        //
        // Теперь: кандидаты отбираются ОДИН раз, и для каждой прогулки
        // двоичным поиском находится граница окна. `sorted` уже
        // по возрастанию даты — на этом и стои́т поиск.
        let кандидаты = sorted.filter {
            $0.kind == .outing && $0.outcome == nil && $0.walkEventID == nil
        }
        guard !кандидаты.isEmpty else { return [:] }

        var result: [UUID: LogEvent] = [:]
        var taken = Set<UUID>()
        for walk in sorted where walk.kind == .walk {
            // Граница: первый кандидат ПОЗЖЕ прогулки. Всё, что левее
            // неё, — не позже, как и требует прежнее условие
            // `candidate.date <= walk.date`.
            var низ = 0, верх = кандидаты.count
            while низ < верх {
                let середина = (низ + верх) / 2
                if кандидаты[середина].date <= walk.date {
                    низ = середина + 1
                } else {
                    верх = середина
                }
            }
            // Назад от границы, пока не вышли из окна. Массив
            // отсортирован, поэтому первый же кандидат вне окна значит,
            // что и все предыдущие вне его: `last` искал самый поздний,
            // и здесь он находится первым.
            var i = низ - 1
            while i >= 0,
                  walk.date.timeIntervalSince(кандидаты[i].date) <= outingIntoWalk {
                if !taken.contains(кандидаты[i].id) {
                    result[walk.id] = кандидаты[i]
                    taken.insert(кандидаты[i].id)
                    break
                }
                i -= 1
            }
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
    ///
    /// Отрицательного «дома» не бывает, а разность в минус — бывает:
    /// `now` у экрана это снимок, который двигает тик раз в тридцать
    /// секунд, а запись о вернувшейся прогулке приходит с настоящим
    /// временем. Между этими двумя «сейчас» конец выхода оказывается
    /// в будущем.
    ///
    /// Раньше минус уходил в `nil` — то есть в то же самое, чем
    /// отвечается «выходов нет вовсе». Экран читал `nil` буквально
    /// и писал «Сегодня ещё не выходили» над лентой, где стояли две
    /// прогулки; то же отвечала Siri. Тестировщица сообщила об этом
    /// дважды: «Выводили собаку, пишет что не выводили» 23.09 и кадром
    /// 24.09 — прогулка 14:13–16:01 при метке «сейчас · 16:00».
    ///
    /// Поэтому минус — это ноль: дома нисколько, только что вернулись.
    /// `nil` остаётся ответом ровно на один вопрос — выходов не было.
    /// Сколько раз выходили за день — человеческим счётом.
    ///
    /// Считаются **блоки**, а не события: три отметки внутри одной
    /// прогулки — это один выход, а не три. Живёт здесь, потому что
    /// `TimelineBlock.isOuting` знает то, чего не знает событие, —
    /// что прогулка и выход по нужде оба считаются выходом.
    ///
    /// **Одна реализация нарочно.** До 28.09 экран считал блоки сам,
    /// а карточка сводки — события `.outing`, и на одном кадре отзыва
    /// стояло «2 выхода из 4 за день» над «3 выхода». Обе арифметики
    /// были верны; расходились смыслы, и тест такого не видит
    /// по устройству — поймал кадр.
    static func outingsCount(_ events: [LogEvent], on day: Date) -> Int {
        blocks(Diary.onDay(events, day)).filter(\.isOuting).count
    }

    static func timeIndoorsNow(_ blocks: [TimelineBlock], now: Date,
                               threshold: TimeInterval) -> TimeInterval? {
        guard let last = blocks.last(where: \.isOuting) else { return nil }
        let interval = max(0, now.timeIntervalSince(last.endedAt))
        return interval >= threshold ? interval : nil
    }
}

/// Разовое связывание отметок с их прогулками у тех, кто гулял
/// до появления связи.
///
/// Связью служила подпись «на прогулке» словами — по ней и восстанавливаем,
/// с проверкой по времени: отметка должна попадать в окно прогулки.
enum WalkLinkMigration {
    static let legacyNote = "на прогулке"

    /// Дольше этого отметка к прогулке уже не относится, даже если других
    /// прогулок в этот день не было.
    static let maxReach: TimeInterval = 4 * 3600

    /// Проставить связи. Возвращает, сколько отметок нашли свою прогулку.
    ///
    /// Ищем не по длительности, а по соседству: отметка принадлежит
    /// последней прогулке, начавшейся раньше неё, — и только если между
    /// ними не началась другая.
    ///
    /// По длительности не выходит: она считается **без пауз**. В живом
    /// дневнике нашлась прогулка на пятнадцать минут, отметки которой
    /// стоят через тридцать три — человек постоял у магазина, — и окно
    /// по длительности их не захватывало.
    @discardableResult
    static func link(_ events: [LogEvent]) -> Int {
        let walks = events.filter { $0.kind == .walk && $0.deletedAt == nil }
            .sorted { $0.date < $1.date }
        guard !walks.isEmpty else { return 0 }

        var linked = 0
        for event in events where event.walkEventID == nil && event.note == legacyNote {
            guard let walk = walks.last(where: { $0.date <= event.date }) else { continue }
            // Между прогулкой и отметкой началась следующая — значит,
            // отметка уже из неё.
            let nextStarted = walks.first { $0.date > walk.date && $0.date <= event.date }
            guard nextStarted == nil else { continue }
            guard event.date.timeIntervalSince(walk.date) <= maxReach else { continue }

            event.walkEventID = walk.id
            linked += 1
        }
        return linked
    }
}
