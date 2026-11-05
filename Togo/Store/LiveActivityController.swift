import Foundation
import ActivityKit
import WidgetKit

/// Управление Live Activity идущего выхода и снимком для виджетов.
///
/// Приложение — единственный, кто пишет: виджет только читает.
enum LiveActivityController {

    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func startWalk(dogName: String, by person: String, at date: Date,
                          tally: String? = nil, кобель: Bool = false) {
        // Список живых активностей — единственный источник правды.
        // Своей копии не держим: она разъедется после перезапуска приложения.
        guard isAvailable, Activity<WalkActivityAttributes>.activities.isEmpty else { return }
        do {
            _ = try Activity.request(
                attributes: WalkActivityAttributes(dogName: dogName, startedBy: person, кобель: кобель),
                content: .init(state: .init(startedAt: date, tally: tally),
                               staleDate: date.addingTimeInterval(4 * 3600)),
                pushType: nil
            )
        } catch {
            log.notice("Live Activity не запустилась: \(error.localizedDescription)")
        }
    }

    /// Пауза на экране блокировки.
    ///
    /// Свой таймер Live Activity ведёт сама, от `startedAt`, и остановить
    /// его на ходу нельзя. Поэтому на паузе активность гасим, а на
    /// «Продолжить» запускаем заново от смещённого начала — так на
    /// блокировке видно то же время, что и в приложении. Раньше пауза
    /// до экрана блокировки не доходила вовсе: приложение говорило
    /// «на паузе», а часы там продолжали идти.
    static func pauseWalk() async {
        await finishWalk(outcome: nil)
    }

    /// Возобновить показ. `startedAt` сдвигаем на всё, что простояли,
    /// чтобы таймер продолжился с той же цифры.
    static func resumeWalk(dogName: String, by person: String, effectiveStart: Date,
                           tally: String? = nil, кобель: Bool = false) {
        startWalk(dogName: dogName, by: person, at: effectiveStart, tally: tally, кобель: кобель)
    }

    /// Погасить всё, что осталось от прошлых запусков.
    ///
    /// `startWalk` намеренно не создаёт вторую активность, если одна уже
    /// живёт. Но живой могла остаться и активность от прогулки, которую
    /// давно забыли: приложение сняли из многозадачности, сессия протухла
    /// через восемь часов, а на блокировке всё ещё «гуляем». Тогда
    /// следующая прогулка оставалась вообще без Live Activity.
    nonisolated static func discardStale() async {
        await finishWalk(outcome: nil)
    }

    /// Гасим всё, что осталось живого: активность могла пережить перезапуск.
    nonisolated static func finishWalk(outcome: String?) async {
        let state = WalkActivityAttributes.ContentState(startedAt: .now, outcome: outcome)
        for activity in Activity<WalkActivityAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    /// Снимок для виджетов пересобирается из тех же данных, что и главный экран,
    /// чтобы виджет и приложение никогда не расходились.
    static func publishSnapshot(dog: Dog?, appState: AppState, now: Date = Date()) {
        publishSnapshot(dog: dog,
                        episodeActive: appState.isEpisodeActive,
                        walkStartedAt: appState.walkStartedAt,
                        walkStartedBy: appState.walkStartedBy,
                        now: now)
    }

    /// То же без `AppState` — для путей, где экрана нет.
    ///
    /// **Заведено 29.10.2026, потому что снимок писал ровно один путь
    /// из шести.** Звал его тик «Сегодня» — то есть открытое приложение.
    /// Отметка голосом, меткой у двери, кнопкой живой активности или
    /// чужая запись, приехавшая со второго телефона тихим пушем, до
    /// виджета не доезжали, пока человек сам не открывал приложение:
    /// отзыв «виджет отстаёт» был про это. `AppState` у тех путей нет
    /// по устройству — у интента и у приёма обмена нет экрана, — поэтому
    /// три величины, которые брались из него, приходят параметрами,
    /// а собирает их `WidgetRefresh` из базы и из сохранённой прогулки.
    static func publishSnapshot(dog: Dog?, episodeActive: Bool,
                                walkStartedAt: Date?, walkStartedBy: String?,
                                now: Date = Date()) {
        guard let dog else { return }
        let events = dog.events
        let signals = Diary.signals(events, now: now, episodeActive: episodeActive)
        let verdict = VerdictEngine.evaluate(signals)
        // Счёт от туалета — `ToiletClock`, тем же вызовом, что у героя
        // «Сегодня»; выход — конец последнего блока ленты, тоже как там.
        // **Сколько кормлений СЕГОДНЯ, а не сколько их в режиме.**
        // Здесь стояло `dog.mealsPerDay`, и это тот же класс, что
        // починен в «Питании» 05.11.2026: читатель расписания,
        // не знающий про разовое исключение. Обычно числа совпадают,
        // но человек, сдвинувший кормление, видел на локскране «1 из 3»
        // при двух пунктах в плане дня — две поверхности спорили
        // друг с другом в один вечер.
        //
        // Откат на `mealsPerDay` оставлен для профиля без часов вовсе:
        // «1 из 0» было бы хуже, чем «1 из 3».
        let часыСегодня = dog.часыКормленийНа(now, calendar: .current)
        let запланированоКормлений = часыСегодня.isEmpty ? dog.mealsPerDay : часыСегодня.count
        let туалет = ToiletClock.last(events, male: dog.sex == .male, now: now)
        let выход = TimelineBuilder.blocks(Diary.active(events)).last(where: \.isOuting)?.endedAt

        let snapshot = WidgetSnapshot(
            dogName: dog.displayName,
            dogInitial: dog.initial,
            verdictTitle: verdict.title,
            // ЧИТАТЕЛЯ-НЕТ-verdictBadge: считается из настоящего
            // вердикта и не показывается ни одной поверхностью.
            verdictBadge: verdict.badge,
            sinceUrineSeconds: signals.sinceUrine,
            urineSilenceSince: signals.urineSilence,
            lastStoolSummary: signals.lastStool.map { "стул \(Fmt.clock($0))" },
            lastWalkSummary: signals.lastWalk.map { "гулял \(Fmt.duration(now.timeIntervalSince($0))) назад" },
            walkStartedAt: walkStartedAt,
            walkStartedBy: walkStartedBy,
            // Та же величина, из которой рядом собирается
            // `lastWalkSummary`, — но датой. Строку виджет показать
            // может, а считать по ней время не может: она застывает
            // в момент публикации.
            lastWalkAt: signals.lastWalk,
            fastingEndsAt: fastingEnd(for: dog, now: now),
            lastMealAt: мяЕда(events, now: now).0,
            mealsToday: мяЕда(events, now: now).1,
            mealsPlanned: запланированоКормлений,
            updatedAt: now,
            lastToiletAt: туалет?.когда,
            lastToiletAtHome: туалет.map { $0.где == .дом },
            lastOutingEndedAt: выход
        )
        // Перечитать ленту виджета — только если снимок сказал новое.
        //
        // Бюджет перезагрузок у виджета конечен, а пересобирается снимок
        // теперь на каждом сохранении базы, в том числе фоновом. Тик
        // «Сегодня» раз в минуту менял бы его всегда: три поля здесь —
        // интервалы и метка времени, посчитанные от `now`. Сравнение
        // их не видит; всё, что виджет показывает живым, он считает
        // от дат сам (`SnapshotText.sinceText(_:now:)`).
        let прежний = WidgetBridge.read()
        WidgetBridge.publish(snapshot)
        guard безЧасов(прежний) != безЧасов(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Снимок без величин, которые меняются от одного хода часов.
    private static func безЧасов(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        var s = snapshot
        s.sinceUrineSeconds = nil
        s.lastWalkSummary = nil   // ЧИТАТЕЛЯ-НЕТ-lastWalkSummary
        s.updatedAt = .distantPast   // ЧИТАТЕЛЯ-НЕТ-updatedAt
        return s
    }

    /// Окно «не кормить» — тем же правилом, что и главный экран.
    ///
    /// **Здесь лежала третья реализация**, и она знала только окно ПОСЛЕ
    /// отметки приёма: перебирала лекарства руками и складывала
    /// `givenAt + fastingMinutes`. Значит виджет молчал в двух случаях
    /// из трёх — про окно ДО дозы (желудок должен быть пустым к приёму)
    /// и про сдвиг часа приёма: передвинули таблетку с 7:00 на 9:00,
    /// а на локскране по-прежнему «не кормить до 8:00».
    ///
    /// Сторож `FastingWindowSecondImplementationTests` этого не поймал:
    /// он ищет вызовы `fastingEnds(`, а здесь расчёт был написан
    /// вручную и ничего не звал. **Сторож на вызов ловит «не позвали»
    /// и слеп к «посчитали сами».**
    ///
    /// Та же болезнь, что у Timer с подписью на «острове» и у Togo
    /// с `Formatting`: правку сделали на одной поверхности из трёх.
    private static func fastingEnd(for dog: Dog, now: Date) -> Date? {
        guard dog.isOnTreatment else { return nil }
        return FeedingGate.block(for: dog.medications, now: now)?.freeAt
    }

    /// Когда кормили последний раз и сколько раз за сегодня.
    ///
    /// **Замер 23.09.2026 по журналу с телефона:** пять сессий из
    /// четырнадцати начинаются с записи еды, и еда — самое частое
    /// действие вообще (17 из 112). Приложение открывают, чтобы
    /// покормить. Виджет при этом говорил про мочу, стул и прогулку —
    /// и про еду не говорил ничего.
    private static func мяЕда(_ events: [LogEvent], now: Date,
                              calendar: Calendar = .current) -> (Date?, Int) {
        let еда = events.filter { $0.kind == .meal && $0.deletedAt == nil }
        let сегодня = еда.filter { calendar.isDate($0.date, inSameDayAs: now) }
        return (еда.map(\.date).max(), сегодня.count)
    }

}
