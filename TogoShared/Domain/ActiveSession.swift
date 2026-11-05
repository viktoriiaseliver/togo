import Foundation

/// Идущий выход или прогулка.
///
/// Разница не в длительности, а в том, зачем вышли. Выход — по нужде,
/// две минуты, у него один вопрос в конце: сходил или нет. Прогулка —
/// это режим: таймер идёт, а человек по ходу отмечает, что собака сделала,
/// одной рукой и не думая.
///
/// Время считается от `startedAt`, а не счётчиком: приложение можно свернуть,
/// заблокировать телефон и убрать в карман — секунды не собьются.
nonisolated struct ActiveSession: Equatable, Sendable, Codable {
    enum Kind: String, Sendable, Codable {
        case outing
        case walk

        var title: String {
            self == .outing ? String(localized: "Выход") : String(localized: "Прогулка")
        }
        var runningTitle: String {
            self == .outing ? String(localized: "выход идёт") : String(localized: "гуляем")
        }
        var pausedTitle: String {
            self == .outing ? String(localized: "выход на паузе") : String(localized: "на паузе")
        }
    }

    struct Mark: Equatable, Identifiable, Sendable, Codable {
        enum Kind: String, CaseIterable, Sendable, Codable {
            case urine, stool, water, treat, training, reaction, incident, note

            var title: String {
                switch self {
                case .urine: String(localized: "Пописал")
                case .stool: String(localized: "Стул")
                case .water: String(localized: "Попил")
                case .treat: String(localized: "Лакомство")
                case .training: String(localized: "Занятие")
                case .reaction: String(localized: "Сорвался")
                case .incident: String(localized: "Инцидент")
                case .note: String(localized: "Заметка")
                }
            }

            var symbol: String {
                switch self {
                case .urine: "drop"
                case .stool: "leaf"
                case .water: "waterbottle"
                case .treat: "sparkles"
                case .training: "target"
                case .reaction: "bolt"
                case .incident: "exclamationmark.triangle"
                case .note: "text.alignleft"
                }
            }

            /// В какую запись ленты превращается отметка.
            var logKind: LogKind {
                switch self {
                case .urine: .outing
                case .stool: .stool
                case .water: .water
                case .treat: .treat
                case .training: .training
                case .reaction: .reaction
                case .incident: .incident
                case .note: .note
                }
            }

            /// Отметки, которые ставят по несколько раз за прогулку.
            ///
            /// Срыв — как раз такая: у реактивной собаки их бывает пять
            /// за один выход, и важно именно количество. А вот занятие,
            /// инцидент и заметка — по одной: второй тап по ним почти
            /// всегда промах, а не второе событие.
            var isRepeatable: Bool {
                self == .urine || self == .stool || self == .water || self == .reaction
            }
        }

        var id = UUID()
        var kind: Kind
        var at: Date

        init(kind: Kind, at: Date = Date()) {
            self.kind = kind
            self.at = at
        }
    }

    var kind: Kind
    var startedAt: Date
    var startedBy: String
    var marks: [Mark] = []

    /// Когда поставили на паузу. Пауза нужна не для красоты: зашли
    /// в магазин, встретили знакомого, ждёте у перехода — время идёт,
    /// а прогулки в этот момент нет.
    /// Прогулку закончили С ЭКРАНА БЛОКИРОВКИ, записей ещё нет.
    ///
    /// **Решение Виктории 27.10.2026, и оно отменяет записанное
    /// дважды.** Круг 2 §6 и круг 3 §1 говорили: «„Домой" убираем,
    /// конец прогулки остаётся в приложении», и довод был наш:
    /// у необратимого действия человек должен быть предупреждён ДО,
    /// а на блокировке его никто не предупредит. Её слово сегодня:
    /// «+ возможность закончить прогулку».
    ///
    /// # Почему поле, а не прямое завершение
    ///
    /// Записи прогулки создаёт ПРИЛОЖЕНИЕ: `WalkMode.finish` зовёт
    /// `EventLog.record`, которому нужен `ModelContext`. У интента
    /// с экрана блокировки его нет и быть не может — это другой
    /// процесс, и база ему не принадлежит.
    ///
    /// Поэтому интент делает ровно то, что может: останавливает
    /// отсчёт и ставит эту метку. Приложение при следующем открытии
    /// видит её, дописывает записи и показывает итог — тот самый,
    /// который на блокировке показать было негде.
    ///
    /// > **Цена названа, а не замолчана: между нажатием и открытием
    /// > приложения записей в дневнике НЕТ.** Отметки прогулки при
    /// > этом целы — они лежат здесь же, в `marks`, и не теряются.
    /// > Потерять их может только `staleAfter`: забытая на сутки
    /// > сессия стирается, и вместе с ней уйдут отметки. Это
    /// > и есть плата за кнопку, которой дизайн не хотел.
    var закончиласьНаБлокировке: Date?

    var pausedAt: Date?
    /// Сколько уже простояли на паузе за эту прогулку.
    var pausedTotal: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }

    /// Чистое время прогулки: без пауз.
    func duration(at now: Date = Date()) -> TimeInterval {
        let raw = max(0, now.timeIntervalSince(startedAt))
        let current = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, raw - pausedTotal - current)
    }

    mutating func pause(at now: Date = Date()) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date = Date()) {
        guard let pausedAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    func count(of kind: Mark.Kind) -> Int {
        marks.filter { $0.kind == kind }.count
    }

    /// Сколько раз собака **опорожнилась** за этот выход — не сколько раз
    /// пометила.
    ///
    /// **Отзыв 28.10.2026, 08:47: «У меня кастрированный кобель, почему
    /// считает мочу много раз?»** Вопрос про сводку прогулки: она
    /// печатала «8 раз пописал» по числу тапов.
    ///
    /// Тапы настоящие — это не дубли. `DuplicateGuard.repeatableWindow`
    /// отсекает только двойной тап в десяти секундах; замер 07.10.2026
    /// по журналу действий показал, что настоящие повторы внутри одной
    /// прогулки идут от 36 секунд. Кобель метит, и каждая метка —
    /// честная отметка человека.
    ///
    /// Но **писание и опорожнение — разные величины, и у Togo это уже
    /// измерено**: `Diary.sameEmptyingWindow` = 45 минут, и заведено оно
    /// ровно потому, что «за одну прогулку собака метит три раза
    /// за десять минут», а медиана интервалов от этого уезжала вниз
    /// и вердикт начинал считать нормой десять минут.
    ///
    /// > **Правило было, а до человека не доезжало.** Домен считал им
    /// > вердикт; сводка прогулки печатала число тапов словом
    /// > «пописал» — то есть приложение само знало, что это одно
    /// > опорожнение, и говорило обратное.
    ///
    /// # Почему по времени, а не по полу
    ///
    /// Решение названо здесь, потому что напрашивается противоположное
    /// (`Dog.sexRaw`, `Dog.isNeutered` — поля есть).
    ///
    /// 1. **Окно уже измерено и работает для любой собаки.** Правило
    ///    на пол было бы ВТОРОЙ копией одного правила, а чем это
    ///    кончается, у Togo записано на `Episode.quietPeriod`: «две
    ///    копии одного числа не расходятся, пока вторую никто не зовёт».
    /// 2. **`sexRaw` ненадёжен, и это замер, а не опасение.** 08.10.2026
    ///    по живой выгрузке: у всех шестнадцати собак `unknown`,
    ///    включая Стича; поле в профиле завели позже
    ///    (`Editors.swift:139`). А `Tools/собрать-архив-стича-полный.py`
    ///    на 28.10 утверждает `isNeutered: False` при её словах
    ///    «кастрированный кобель». Правило, стоящее на поле, которое
    ///    спорит с хозяином, заставило бы приложение спорить с ней —
    ///    ровно та жалоба, которую чиним.
    /// 3. **Метит не только кобель.** Сука метит реже, но метит, и у неё
    ///    та же сводка.
    ///
    /// Счёт — тот же, что в `Diary.urineIntervals`: промежутки между
    /// СОСЕДНИМИ отметками, и считается тот, что шире окна. Не «кластер
    /// от первой»: это было бы второе правило с тем же именем.
    var опорожнений: Int {
        let времена = marks.filter { $0.kind == .urine }.map(\.at).sorted()
        guard !времена.isEmpty else { return 0 }
        var всего = 1
        for (предыдущее, текущее) in zip(времена, времена.dropFirst())
        where текущее.timeIntervalSince(предыдущее) > Diary.sameEmptyingWindow {
            всего += 1
        }
        return всего
    }

    /// Сколько раз собака сорвалась за этот выход.
    var reactions: Int { count(of: .reaction) }

    /// Короткая сводка для карточки и для итога: «моча 2 · стул · вода».
    var tally: String {
        let order: [Mark.Kind] = [.urine, .stool, .water, .treat, .training, .reaction, .incident]
        let parts: [String] = order.compactMap { kind in
            let count = count(of: kind)
            guard count > 0 else { return nil }
            return count > 1 ? "\(kind.title.lowercased()) ×\(count)" : kind.title.lowercased()
        }
        return parts.isEmpty ? String(localized: "пока ничего не отмечено") : parts.joined(separator: " · ")
    }

    /// Результат выхода выводится из отметок — спрашивать лишний раз незачем.
    var outcome: OutingOutcome? {
        let urine = count(of: .urine) > 0
        let stool = count(of: .stool) > 0
        switch (urine, stool) {
        case (true, true): return .both
        case (true, false): return .urine
        case (false, true): return .stool
        case (false, false): return marks.isEmpty ? nil : OutingOutcome.none
        }
    }
}


/// Хранение идущей прогулки между запусками.
///
/// Прогулка длится полчаса, и всё это время телефон лежит в кармане:
/// система вправе выгрузить приложение в любой момент. Пока сессия жила
/// только в памяти, это означало сброшенный таймер и «начинай заново» —
/// ровно то, на что и жаловались.
nonisolated enum ActiveSessionStore {
    private static let key = "active.session"

    private static var defaults: UserDefaults {
        AppGroupDefaults.shared
    }

    /// Дольше этого прогулка почти наверняка забыта, а не идёт.
    /// Подбирать не из головы: восемь часов — это уже не выход с собакой.
    static let staleAfter: TimeInterval = 8 * 3600

    /// Прогулка началась, кончилась или получила отметку — кем угодно.
    ///
    /// Заведено 29.10.2026 ради виджета. Прогулку пишут четыре двери:
    /// экран (`AppState.session`), метка и Siri (`WalkControl`),
    /// кнопки живой активности (`WalkMarkIntent`, `WalkFinishIntent`).
    /// Снимок виджета пересобирал только экран «Сегодня», и прогулка,
    /// начатая меткой у двери, на виджете не появлялась вовсе, а
    /// законченная с блокировки — тикала «На улице» до открытия
    /// приложения. Слушать одно уведомление дешевле, чем помнить
    /// четыре места вызова: пятая дверь придёт сюда же сама.
    ///
    /// Слушает приложение (`WidgetRefresh`); в расширении слушателя
    /// нет, и уведомление там ничего не стоит.
    static let изменилась = Notification.Name("togo.activeSession.changed")

    static func save(_ session: ActiveSession?) {
        defer { NotificationCenter.default.post(name: изменилась, object: nil) }
        guard let session else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    /// Прочитать, изменить, записать обратно.
    ///
    /// Нужно тем, кто отмечает мимо экранов: кнопка на живой активности
    /// нажимается, когда приложение в фоне, и его копия прогулки в памяти
    /// может быть старше сохранённой.
    @discardableResult
    static func mutate(_ change: (inout ActiveSession) -> Void) -> ActiveSession? {
        guard var session = load() else { return nil }
        change(&session)
        save(session)
        return session
    }

    /// Поставить отметку на идущей прогулке.
    static func appendMark(_ kind: ActiveSession.Mark.Kind,
                           at date: Date = Date()) -> ActiveSession? {
        mutate { session in
            // То же правило, что и в приложении: неповторяемое
            // переключается, а не копится.
            if !kind.isRepeatable, session.count(of: kind) > 0 {
                session.marks.removeAll { $0.kind == kind }
            } else {
                session.marks.append(ActiveSession.Mark(kind: kind, at: date))
            }
        }
    }

    static func load(now: Date = Date()) -> ActiveSession? {
        guard let data = defaults.data(forKey: key),
              let session = try? JSONDecoder().decode(ActiveSession.self, from: data)
        else { return nil }

        // Забытую прогулку не воскрешаем: показать через сутки таймер
        // на девятнадцать часов — хуже, чем не показать ничего.
        guard now.timeIntervalSince(session.startedAt) < staleAfter else {
            save(nil)
            return nil
        }
        return session
    }
}
