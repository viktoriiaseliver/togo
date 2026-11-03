import Foundation

/// Выборки по ленте. Отдельно от SwiftData, чтобы считалось одинаково
/// в приложении, в виджете и в тестах.
nonisolated enum Diary {
    static func active(_ events: [LogEvent]) -> [LogEvent] {
        events.filter { !$0.isDeleted && !служебная($0) }
    }

    /// Запись, которой человек не делал: артефакт отладочной сборки.
    ///
    /// # Это ВТОРОЙ запрет, а не копия первого
    ///
    /// Первый слой — `SharedDiaryOutgoing.sendable(_:)` — запрещает
    /// **отправлять** такую запись второму человеку. Этот запрещает
    /// **показывать** её хозяину как его данные. Снаружи они выглядят
    /// одним предметом «служебная запись», и это ловушка: читающий
    /// решит, что один из двух лишний.
    ///
    ///     снимешь запрет отправки   запись уедет маме
    ///     снимешь этот              у неё же сломается вердикт
    ///
    /// # Что ломалось без него
    ///
    /// `CloudKitSchemaWarmup` пишет запись датой 1 января 2001 года.
    /// Замер 08.10.2026 по выгрузке с телефона Виктории: из 182 записей
    /// одна такая, автор `ПРОГРЕВ СХЕМЫ`, у видимой собаки «Стич»;
    /// самая ранняя настоящая запись — 2026-09-01, то есть запас
    /// двадцать четыре года, и порог не на краю.
    ///
    /// Отсюда `daysOfData` давал ≈9410 дней при двух настоящих
    /// событиях, и красная линия Togo — «меньше четырёх дней данных:
    /// всегда „непонятно“, приложение не знает лучше хозяина» —
    /// становилась **непроходимой вниз**: `VerdictEngine` сравнивает
    /// с `minimumDaysOfData` = 4, и `guard` проходил всегда.
    ///
    /// Читателей было три, и не фильтровал ни один:
    ///
    ///     NeedVerdict:144        уверенный вердикт на двух событиях
    ///     DataPrivacyScreen:29   экран «Данные» печатал «9410 дней» —
    ///                            то есть неправду о данных на экране,
    ///                            существующем ради правды о них
    ///     Exporter.csv:18,56     выгрузка уезжает ЦЕЛИКОМ: окна у неё
    ///                            нет вовсе, в отличие от отчёта врачу,
    ///                            который фильтрует месяцем
    ///
    /// # Признак — дата, а не имя автора
    ///
    /// Метка стоит и в `authorName`, но опираться на неё нельзя:
    /// `LogEvent` ездит в общий дневник, и слияние переписывает
    /// `authorName` из приехавшего payload. Дату не переписывает никто.
    /// Измерено 23.09 и записано в голове самого прогрева
    /// (`CloudKitSchemaWarmup:35-40`).
    ///
    /// # Константа чужая НАРОЧНО, и это третий читатель, а не третья копия
    ///
    /// Три вопроса разные, а порог один и к вопросам не относится:
    /// раньше 2020 года записи в дневнике собаки быть не может,
    /// приложению меньше года.
    ///
    ///     CloudKitSchemaWarmup.доПрограммы   что удалять, убирая
    ///                                        прогрев (под `#if DEBUG`)
    ///     SharedDiaryOutgoing (отправка)     вправе ли мы положить это
    ///                                        в чужое хранилище
    ///     здесь (показ)                      вправе ли мы показать это
    ///                                        человеку как его данные
    ///
    /// Сдвинешь — посмотри на все три:
    /// `grep -rn "доПрограммы\|раньшеПриложения"`.
    ///
    /// В `Domain` константа не перенесена нарочно: перенос файла
    /// в общем дереве теряет причину переезда легче, чем код, —
    /// на этом проекте это уже случилось 08.10.
    ///
    /// # Чего этот запрет НЕ делает
    ///
    /// Не убирает уже уехавшее и хранилища не трогает: запись остаётся
    /// в базе, она лишь перестаёт считаться данными человека. Убрать её
    /// из живых данных приложение не умеет вовсе — `CloudKitSchemaWarmup`
    /// целиком под `#if DEBUG`, и `create`, и `remove()`. А кнопка
    /// прогрева жива (`SettingsScreen`), то есть следующий заход
    /// из отладочной сборки заведёт метку заново — и этот запрет нужен
    /// будет снова.
    static func служебная(_ event: LogEvent) -> Bool {
        event.date < SharedDiaryOutgoing.раньшеПриложения
    }

    static func onDay(_ events: [LogEvent], _ day: Date, calendar: Calendar = .current) -> [LogEvent] {
        active(events)
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    /// Все записи, разложенные по дням, ОДНИМ проходом.
    ///
    /// # Зачем, когда рядом есть `onDay`
    ///
    /// `onDay` отвечает про ОДИН день и для одного дня честен. Беда
    /// начинается, когда дней много: он зовётся в цикле, и каждый вызов
    /// заново проходит ВЕСЬ массив, вызывая
    /// `Calendar.isDate(_:inSameDayAs:)` — одну из самых дорогих
    /// операций Foundation. Замер 28.10.2026 по жалобе «виснет, плохо
    /// скроллится»:
    ///
    /// ```
    /// HistoryScreen.chartPoints   30 дней × onDay(filtered)
    ///                             а `filtered` — ВЫЧИСЛЯЕМОЕ свойство,
    ///                             то есть пересчитывается все 30 раз
    /// MonthCalendar.marker        42 ячейки сетки × onDay(events)
    /// итого при 1400 записях      ~100 000 вызовов Calendar.isDate
    ///                             НА КАЖДУЮ перерисовку экрана
    /// ```
    ///
    /// Здесь на запись приходится один `startOfDay` вместо сорока двух
    /// сравнений, и дальше день достаётся из словаря за O(1). Проход
    /// по всем записям сам по себе дёшев — дорого было проходить их
    /// заново на каждый день.
    ///
    /// > **Стоимость росла не от числа записей, а от ПРОИЗВЕДЕНИЯ
    /// > записей на дни.** Поэтому она и не была видна, пока дневник
    /// > вели руками: у человека с тремя записями в день календарь
    /// > месяца стоил столько же, сколько у человека с тысячей.
    ///
    /// Внутри дня порядок тот же, что у `onDay` — по времени: ленту
    /// читают сверху вниз, и два источника одного порядка расходиться
    /// не должны.
    ///
    /// - Returns: ключ — начало дня в переданном календаре. Пустых
    ///   дней в словаре нет: читатель обязан считать отсутствие ключа
    ///   днём без записей, а не ошибкой.
    static func поДням(_ events: [LogEvent],
                       calendar: Calendar = .current) -> [Date: [LogEvent]] {
        Dictionary(grouping: active(events)) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.sorted { $0.date < $1.date } }
    }

    /// День вместе со следом только что удалённого.
    ///
    /// След живёт ровно столько, сколько живёт отмена, — пять секунд.
    /// Раньше зачёркнутая строка оставалась до конца дня, и удалённое
    /// висело в ленте наравне с настоящим. В живом дневнике это видно
    /// сразу: человек не нашёл, где поправить граммы, удалил запись
    /// и записал заново — а в ленте осталось и то и другое.
    ///
    /// Ответ на «я точно это убрала?» даёт тост с кнопкой «Отменить».
    /// Когда он уезжает, вопрос закрыт, и строке в ленте делать нечего.
    /// - Parameter tracing: записи, которые прямо сейчас можно вернуть
    ///   кнопкой в тосте. Список приходит из самого тоста, поэтому
    ///   строка исчезает ровно тогда, когда исчезает возможность отмены,
    ///   а не через полминуты, когда экран в следующий раз тикнет.
    static func onDayWithTraces(_ events: [LogEvent], _ day: Date,
                                tracing: Set<UUID> = [],
                                calendar: Calendar = .current) -> [LogEvent] {
        // Вторая дверь показа — и единственная функция `Diary`, которая
        // НЕ идёт через `active`: она держит свой фильтр удалённого,
        // потому что след отменяемого ей нужен, а `active` его прячет.
        //
        // Запрет на служебное нужен и ей, хотя сегодня он тут ничего
        // не меняет: запись прогрева датирована 2001 годом, а функция
        // ограничена показываемым днём — всплыть она могла бы только
        // у того, кто пролистал ленту до 1 января 2001 года. Предикат
        // стоит здесь не ради сегодняшнего показа, а потому что
        // **запрет в одной двери из двух мы уже оплатили**: вчера
        // на этом проекте ворота стояли в одной из двух дорог наружу,
        // вторая о них не знала, и чужой сторож оставался зелёным.
        // Расширит кто-нибудь эту функцию по дням — дыра откроется
        // молча.
        //
        // Условия сведены в одно замыкание, а не в цепочку `filter`:
        // четыре звена подряд — наш оплаченный класс «срыв типизатора»,
        // где перебор растёт степенью, а жалоба приходит не на то
        // выражение.
        events
            .filter {
                calendar.isDate($0.date, inSameDayAs: day)
                    && ($0.deletedAt == nil || tracing.contains($0.id))
                    && !служебная($0)
            }
            .sorted { $0.date < $1.date }
    }

    static func last(_ events: [LogEvent], kind: LogKind, before date: Date = Date()) -> LogEvent? {
        active(events)
            .filter { $0.kind == kind && $0.date <= date }
            .max { $0.date < $1.date }
    }

    /// Выходы, закончившиеся мочой (или мочой и стулом).
    static func urineEvents(_ events: [LogEvent]) -> [LogEvent] {
        active(events)
            .filter { $0.kind == .outing && ($0.outcome == .urine || $0.outcome == .both) }
            .sorted { $0.date < $1.date }
    }

    /// Сколько времени собака способна терпеть — это промежуток между
    /// **опорожнениями**, а не между отметками.
    ///
    /// За одну прогулку собака метит три раза за десять минут, и раньше
    /// это давало три интервала по десять минут вперемешку с настоящими
    /// четырёхчасовыми. Медиана уезжала вниз, и вердикт начинал считать
    /// нормой десять минут — то есть переставал работать у любого, кто
    /// отмечает прогулку подробно.
    static let sameEmptyingWindow: TimeInterval = 45 * 60

    static func urineIntervals(_ events: [LogEvent]) -> [TimeInterval] {
        let dates = urineEvents(events).map(\.date)
        guard dates.count > 1 else { return [] }
        return zip(dates, dates.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .filter { $0 > sameEmptyingWindow }
    }

    static func daysOfData(_ events: [LogEvent], now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let first = active(events).map(\.date).min() else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days + 1
    }

    static func signals(_ events: [LogEvent], now: Date = Date(), episodeActive: Bool) -> NeedSignals {
        let urine = urineEvents(events).last
        let lastOuting = last(events, kind: .outing, before: now)
        return NeedSignals(
            now: now,
            lastUrine: urine?.date,
            lastStool: active(events)
                .filter { $0.kind == .stool || ($0.kind == .outing && ($0.outcome == .stool || $0.outcome == .both)) }
                .max { $0.date < $1.date }?.date,
            lastMeal: last(events, kind: .meal, before: now)?.date,
            lastWalk: last(events, kind: .walk, before: now)?.date,
            urineIntervals: urineIntervals(events),
            daysOfData: daysOfData(events, now: now),
            episodeActive: episodeActive,
            lastOutingHadResult: lastOuting?.outcome != nil && lastOuting?.outcome != OutingOutcome.none,
            lastOutingAt: lastOuting?.date
        )
    }

    // MARK: Сводка «ел и пил»

    struct DaySummary {
        var eatenGrams: Int
        var dailyGrams: Int
        var outings: Int
        var meals: Int
        var walkMinutes: Int
        // `trainingGrams` снято 03.11.2026 вместе с единственным
        // читателем (`TodaySummaryStrip:46`). Поле считалось по
        // `kind == .training`, а таких событий не заводит ни один
        // путь с 28.10 — значит оно вечно отдавало ноль, и ноль
        // этот читался как «сегодня не занимались».
    }

    static func summary(_ events: [LogEvent], day: Date, dog: Dog?) -> DaySummary {
        let today = onDay(events, day)
        return DaySummary(
            // Лакомства, взятые из дневной порции, — это та же еда.
            // Не считать их значит показывать «съел 60 из 120», когда
            // тридцать граммов ушло на лакомства.
            eatenGrams: today
                .filter { $0.kind == .meal || ($0.kind == .treat && $0.fromPortion) }
                .compactMap(\.grams)
                .reduce(0, +),
            dailyGrams: dog?.dailyGrams ?? 0,
            // СОБЫТИЯ `.outing`, а не выходы человеческим счётом: три
            // отметки внутри одной прогулки дадут три. Экрану это число
            // не показывают — он берёт `TimelineBuilder.outingsCount`,
            // который считает блоки. Разница видна глазом: 28.09 на кадре
            // отзыва стояло «2 выхода из 4 за день» над карточкой
            // «3 выхода», и оба числа были посчитаны верно.
            outings: today.filter { $0.kind == .outing }.count,
            meals: today.filter { $0.kind == .meal }.count,
            walkMinutes: today.filter { $0.kind == .walk }.compactMap(\.durationSeconds).reduce(0, +) / 60
        )
    }

    // MARK: «Как попросил»

    /// Спрашиваем не каждый раз: при смене сигнала или раз в пять выходов.
    static func shouldAskHowAsked(_ events: [LogEvent], now: Date = Date()) -> Bool {
        let outings = active(events).filter { $0.kind == .outing }.sorted { $0.date < $1.date }
        guard outings.count >= 2 else { return true }
        let answered = outings.compactMap(\.askSignal)
        guard let lastAnswered = answered.last else { return true }
        let sinceAnswered = outings.reversed().prefix { $0.askSignal == nil }.count
        if sinceAnswered >= 5 { return true }
        // Смена сигнала: последние два ответа разошлись по «спокойный / не спокойный».
        if answered.count >= 2, answered[answered.count - 2].isCalm != lastAnswered.isCalm { return true }
        return false
    }

    struct SignalTally {
        var calm: Int
        var barking: Int
        var total: Int
    }

    static func signalTally(_ events: [LogEvent], from: Date, to: Date) -> SignalTally {
        let signals = active(events)
            .filter { $0.kind == .outing && $0.date >= from && $0.date < to }
            .compactMap(\.askSignal)
        return SignalTally(
            calm: signals.filter(\.isCalm).count,
            barking: signals.filter { $0 == .barked || $0 == .scratchedDoor }.count,
            total: signals.count
        )
    }

    /// Лай вытесняет спокойный сигнал — сравниваем эту неделю с позапрошлой.
    static func barkingIsDisplacingCalm(_ events: [LogEvent], now: Date = Date()) -> Bool {
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now) else { return false }
        let past = signalTally(events, from: twoWeeksAgo, to: weekAgo)
        let current = signalTally(events, from: weekAgo, to: now)
        guard past.total >= 5, current.total >= 5 else { return false }
        let pastShare = Double(past.barking) / Double(past.total)
        let nowShare = Double(current.barking) / Double(current.total)
        return nowShare > 0.4 && nowShare > pastShare * 1.5
    }

    // MARK: Инциденты и эпизод

    /// Второй инцидент за сутки поднимает флаг эпизода.
    static func incidentsInLast24h(_ events: [LogEvent], now: Date = Date()) -> [LogEvent] {
        active(events).filter { $0.kind == .incident && now.timeIntervalSince($0.date) < 24 * 3600 }
    }

    /// Инциденты, из которых складывается эпизод: без туалета дома.
    /// Почему — в голове `EpisodeRaiser`.
    static func episodeIncidentsInLast24h(_ events: [LogEvent], now: Date = Date()) -> [LogEvent] {
        incidentsInLast24h(events, now: now).filter { ($0.incidentKind ?? .other).raisesEpisode }
    }

    /// Час предыстории после лужи: вода, одиночество, последний выход.
    static func hourBefore(_ events: [LogEvent], incident: Date) -> [LogEvent] {
        active(events)
            .filter { $0.date < incident && incident.timeIntervalSince($0.date) < 6 * 3600 && $0.kind != .incident }
            .sorted { $0.date > $1.date }
            .prefix(4)
            .reversed()
    }

    // MARK: Стул

    /// «Как всегда» доступно, только если последние 4 записи совпадают.
    static func usualStool(_ events: [LogEvent]) -> StoolForm? {
        let recent = active(events)
            .filter { $0.kind == .stool && $0.stoolForm != nil }
            .sorted { $0.date > $1.date }
            .prefix(4)
        guard recent.count == 4 else { return nil }
        let forms = Set(recent.compactMap(\.stoolForm))
        let flags = recent.map(\.stoolFlags)
        guard forms.count == 1, flags.allSatisfy(\.isEmpty) else { return nil }
        return forms.first
    }

    /// Два жидких с кровью подряд предлагают выписку.
    static func suggestsVetReport(_ events: [LogEvent]) -> Bool {
        let recent = active(events)
            .filter { $0.kind == .stool }
            .sorted { $0.date > $1.date }
            .prefix(2)
        guard recent.count == 2 else { return false }
        return recent.allSatisfy { $0.stoolForm == .liquid && $0.stoolFlags.contains(.blood) }
    }

    // MARK: Слияние офлайн-записей

    /// Две записи об одном событии в пределах 20 минут дают карточку слияния
    /// обоим авторам — а не тихую перезапись.
    static func mergeCandidates(_ events: [LogEvent], now: Date = Date()) -> [(LogEvent, LogEvent)] {
        // Смотрим только последние сутки: карточка слияния нужна сразу,
        // а не через месяц, и разбирать ради неё всю историю незачем.
        let recent = active(events).filter { now.timeIntervalSince($0.date) < 24 * 3600 }
        let sorted = recent.sorted { $0.date < $1.date }
        var pairs: [(LogEvent, LogEvent)] = []
        for (index, event) in sorted.enumerated() {
            for other in sorted[(index + 1)...] {
                guard other.date.timeIntervalSince(event.date) < 20 * 60 else { break }
                if other.kind == event.kind, other.authorName != event.authorName {
                    pairs.append((event, other))
                }
            }
        }
        return pairs
    }
}
