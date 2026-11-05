import Foundation

/// Срок контроля из назначения. Медицинский слой,
/// `docs/ТЗ-медицинский-слой.md` §2.4 и §3.4.
///
/// ТЗ называет это поле главным в назначении, и вот почему:
///
/// > **Срок контроля — главное поле.** Это единственное место, откуда
/// > приложение может узнать, когда напоминать. Сейчас эти сроки живут
/// > в текстах рецептов, и человек считает их в уме.
///
/// И почему это **диапазон**, а не дата: у Стича три врача назвали три
/// разных интервала — «4–6 недель», «3 недели», «4–8 недель». Свести
/// их к одной дате значит придумать число за врача.
///
/// > из него считается напоминание… в начале окна и в последний день
/// > окна
///
/// Два напоминания, а не одно, потому что окно — это право прийти
/// в любой день, а не обязанность в конкретный.
nonisolated enum ControlWindow {

    /// Что написал врач. Недели, а не дни: так пишут в рецептах,
    /// и перевод в дни здесь, а не в голове у вводящего.
    struct Prescribed: Sendable, Equatable {
        let fromWeeks: Int
        let toWeeks: Int

        /// Одно число («через 3 недели») — тоже окно, шириной в ноль.
        /// Отдельного случая не заводим: он выродился бы в ту же
        /// арифметику с двумя путями.
        init(weeks: Int) {
            self.fromWeeks = weeks
            self.toWeeks = weeks
        }

        init(fromWeeks: Int, toWeeks: Int) {
            self.fromWeeks = min(fromWeeks, toWeeks)
            self.toWeeks = max(fromWeeks, toWeeks)
        }
    }

    /// Окно датами.
    struct Window: Sendable, Equatable {
        let opens: Date
        let closes: Date
    }

    /// Посчитать окно от даты назначения.
    ///
    /// Календарь приходит параметром, а не `.current`: иначе тест
    /// зависел бы от часового пояса машины, и у нас уже был замер,
    /// где журнал в UTC, а дневник в местном, и первый проход дал ноль.
    static func window(prescribedAt: Date,
                       _ prescribed: Prescribed,
                       calendar: Calendar = .current) -> Window? {
        guard prescribed.fromWeeks >= 0 else { return nil }
        guard let opens = calendar.date(byAdding: .weekOfYear,
                                        value: prescribed.fromWeeks,
                                        to: prescribedAt),
              let closes = calendar.date(byAdding: .weekOfYear,
                                         value: prescribed.toWeeks,
                                         to: prescribedAt)
        else { return nil }
        return Window(opens: opens, closes: closes)
    }

    /// Где человек относительно окна.
    enum Stage: Sendable, Equatable {
        /// Рано: окно откроется такого-то числа.
        case beforeWindow(opens: Date)
        /// Окно открыто, можно идти.
        case open(closes: Date)
        /// Последний день окна.
        case lastDay
        /// Окно прошло, и контроля не было.
        case missed(closedAt: Date)
    }

    /// Ступень на сегодня.
    ///
    /// «Последний день» выделен отдельно, а не выведен из `open`,
    /// потому что это **разные новости**, и одним текстом их покрывать
    /// нельзя: «можно сдать до 20-го» и «сегодня последний день» —
    /// разные действия человека. У Togo за один текст на несколько
    /// причин уже заплачено ступенью отката iCloud.
    static func stage(_ window: Window,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Stage {
        if now < calendar.startOfDay(for: window.opens) {
            return .beforeWindow(opens: window.opens)
        }
        if calendar.isDate(now, inSameDayAs: window.closes) {
            return .lastDay
        }
        if now > window.closes {
            return .missed(closedAt: window.closes)
        }
        return .open(closes: window.closes)
    }

    /// Когда напоминать. Ровно две даты, как требует ТЗ.
    ///
    /// Возвращает пустой массив, если окно уже прошло: напоминание
    /// о прошедшем сроке — не напоминание, а упрёк, и у нас записано,
    /// что приложение не говорит человеку о собаке того, чего не знает.
    /// О пропущенном окне говорит `Stage.missed` на экране, а не пуш.
    ///
    /// **Мест вызова ноль, и это РЕШЕНИЕ С АДРЕСОМ, а не забытый
    /// долг.** Замер 05.11.2026; контроль взят соседями по этому типу,
    /// чтобы ломаться вместе с предметом — `window`, `stage` и `word`
    /// зовутся по-настоящему из `ReminderScheduler.строкиКонтроля:422-437`
    /// и `PrescriptionScreens.swift:225`. То есть модуль подключён,
    /// и мимо прошла ровно эта функция.
    ///
    /// Причина записана рядом с тем, кто её принял
    /// (`ReminderScheduler.swift:395-404`): **«два дня, а не два
    /// пуша»** — расхождение ТЗ («из него считается напоминание…
    /// в начале окна и в последний день») с правилом прерываний
    /// («только три вещи») решено в сторону правила, и про контроль
    /// говорит дневная сводка словами `ControlWindow.word`, а не
    /// отдельный пуш. То есть **обещание ТЗ исполнено по существу
    /// другим механизмом**, и даты для пушей никому не нужны.
    ///
    /// Снять нельзя по той же записи: расхождение названо
    /// **продуктовым вопросом**, а не закрытым, и у ТЗ §2.4/§3.4
    /// хозяин — Виктория. Удаление тихо закрыло бы пункт ТЗ,
    /// которого никто не отменял.
    static func reminderDates(_ window: Window, now: Date = Date()) -> [Date] {
        [window.opens, window.closes].filter { $0 > now }
    }

    /// Словами, для строки на экране.
    ///
    /// Текст живёт рядом с правилом, а не во вью: иначе вторая
    /// поверхность — «Здоровье», виджет или пуш — напишет своё,
    /// и три формулировки разойдутся молча.
    static func word(_ stage: Stage) -> String {
        switch stage {
        case .beforeWindow:
            String(localized: "контроль ещё не скоро")
        case .open:
            String(localized: "пора на контроль")
        case .lastDay:
            String(localized: "последний день контроля")
        case .missed:
            String(localized: "срок контроля прошёл")
        }
    }
}
