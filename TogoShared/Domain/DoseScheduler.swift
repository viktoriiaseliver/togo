import Foundation
import SwiftData

/// Приёмы препаратов по расписанию.
///
/// До этого вся медицинская часть была мертва: схему завести можно было,
/// а отметок приёма никто не создавал. А от них зависит всё остальное —
/// окно натощак считается от **фактической** отметки, защита от двойной
/// дозы смотрит на отметки, лестница эскалации тоже. Схема была, машинерия
/// вокруг неё не работала ни разу.
nonisolated enum DoseScheduler {
    /// Завести отметки на день, если их ещё нет.
    ///
    /// Делается лениво, при открытии экрана: плодить записи на год вперёд
    /// незачем, а на день — ровно столько, сколько нужно эскалации,
    /// чтобы понимать, что дозу пропустили.
    @MainActor
    @discardableResult
    static func ensureDoses(for dog: Dog, on day: Date = Date(), context: ModelContext) -> Int {
        guard dog.isOnTreatment else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        var created = 0

        var removed = 0

        for medication in dog.medications where !medication.isPaused {
            for minute in medication.times.sorted() {
                let scheduled = calendar.date(minuteOfDay: minute, on: startOfDay)
                let exists = medication.doses.contains {
                    calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
                }
                guard !exists else { continue }

                let dose = DoseRecord(scheduledAt: scheduled)
                dose.medication = medication
                context.insert(dose)
                created += 1
            }

            removed += removeOrphans(of: medication, on: startOfDay,
                                     calendar: calendar, context: context)
        }

        if created > 0 || removed > 0, !context.persist(otherwise: {}) {
            log.error("расписание доз не записалось")
            return 0
        }
        return created
    }

    /// Доза, о которой стоит тревожиться прямо сейчас — или ничего.
    ///
    /// **Почему это здесь, а не в экране.** Раньше выбор жил
    /// в `TodayScreen.overdueDose` и перебирал ВСЕ дозы собаки без
    /// ограничения по дню. Неотмеченная доза из любого прошлого дня
    /// давала третью стадию навсегда и выигрывала как самая ранняя —
    /// то есть красный баннер вставал насовсем. А `Fmt.clock` печатает
    /// только часы и минуты, без даты: доза позавчерашних 21:30
    /// читалась как сегодняшние, и в 18:25 выглядела тревогой о том,
    /// что будет через три часа. Проверить это на экране было нечем:
    /// решение лежало в приватном свойстве вью.
    ///
    /// **Горизонт — сутки, и это не новое правило.** День здесь уже
    /// единица счёта: `ensureDoses(for:on:)` заводит отметки на день,
    /// `removeOrphans` работает по дню, экран называется «Сегодня».
    /// Баннер на «Сегодня» говорит про сегодня. Что было вчера —
    /// история и отчёт врачу, а не тревога сейчас.
    @MainActor
    static func alarmingDose(
        among medications: [Medication], now: Date = Date(),
        calendar: Calendar = .current
    ) -> DoseRecord? {
        medications
            .flatMap(\.doses)
            .filter { calendar.isDate($0.scheduledAt, inSameDayAs: now) }
            .filter { $0.escalationStage(at: now) >= 2 }
            .min { $0.scheduledAt < $1.scheduledAt }
    }

    /// Убрать отметки на час, которого в расписании больше нет.
    ///
    /// **Зачем.** Время приёма правят: завели 13:00, передумали, поставили
    /// 21:30. Отметка на 13:00 при этом оставалась — ничья, никем
    /// не отмечаемая, — и через час после своего часа становилась
    /// просроченной навсегда. 21.09.2026 это выглядело на телефоне как
    /// красное «Доза 21:30 не отмечена» в 14:05: тревога о дозе, до
    /// которой семь часов. Формула эскалации при этом считала верно —
    /// врали данные.
    ///
    /// Красный у Того несёт лекарства, и ложная тревога обесценивает его
    /// весь — поэтому сироту убираем, а не прячем.
    ///
    /// **Трогаем только нетронутые.** Отмеченная, пропущенная, отменённая
    /// или взятая на себя доза — это история и чужое решение; её удаление
    /// было бы куда хуже лишнего баннера.
    @MainActor
    private static func removeOrphans(
        of medication: Medication, on startOfDay: Date,
        calendar: Calendar, context: ModelContext
    ) -> Int {
        let расписание = Set(medication.times)
        var removed = 0
        for dose in medication.doses
        where calendar.isDate(dose.scheduledAt, inSameDayAs: startOfDay) {
            guard dose.givenAt == nil, dose.skippedAt == nil,
                  dose.cancelledAt == nil, dose.claimedAt == nil else { continue }
            let minute = calendar.component(.hour, from: dose.scheduledAt) * 60
                + calendar.component(.minute, from: dose.scheduledAt)
            guard !расписание.contains(minute) else { continue }
            context.delete(dose)
            removed += 1
        }
        return removed
    }

    /// Отметить приём. Возвращает отметку, чтобы экран мог показать,
    /// когда закончится окно натощак.
    @MainActor
    @discardableResult
    static func markGiven(
        _ medication: Medication,
        scheduledAt scheduled: Date,
        by person: String,
        at now: Date = Date(),
        context: ModelContext
    ) -> DoseRecord? {
        let calendar = Calendar.current
        // На одну минуту бывает несколько отметок: у каждого телефона
        // общего дневника своя, с другим id. Данная любым из них — главнее
        // своей открытой, иначе чужое «дано» не остановило бы вторую дозу.
        let наМинуту = medication.doses.filter {
            calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
        }
        let существующая = наМинуту.first { $0.givenAt != nil } ?? наМинуту.first
        let dose = существующая ?? {
            let new = DoseRecord(scheduledAt: scheduled)
            new.medication = medication
            context.insert(new)
            return new
        }()

        // Дважды одну дозу не отмечаем: это и есть защита от двойной дозы.
        guard dose.givenAt == nil else {
            UsageLog.note(.dose, "given", outcome: .duplicate)
            return dose
        }

        let остаток = medication.stockLeft
        dose.givenAt = now
        dose.givenBy = person

        // Счёт таблеток живёт на отметках: отдельного учёта не нужно,
        // минус одна с каждой. Ноль — просто «не считаем».
        if medication.stockTotal > 0, medication.stockLeft > 0 {
            medication.stockLeft -= 1
        }

        // Здесь `try?` стоил бы второй дозы. Экран, получив отметку,
        // снимает догоняющие напоминания на t+30 и t+60. Если сохранение
        // не прошло, а приложение выгрузили, доза снова «не отмечена» —
        // но напоминаний уже нет, и человек не узнает, что отметка
        // потерялась. Он даст лекарство второй раз.
        //
        // Пустой ответ — это сигнал экрану: напоминания не снимать.
        guard context.persist(otherwise: {
            dose.givenAt = nil
            dose.givenBy = nil
            medication.stockLeft = остаток
            if существующая == nil { отцепить(dose, from: context) }
        }) else {
            UsageLog.note(.dose, "given", outcome: .failed)
            return nil
        }
        UsageLog.note(.dose, "given")
        return dose
    }

    /// Убрать вновь созданную отметку, которая так и не легла в хранилище.
    ///
    /// Связь снимаем отдельно: `context.delete` до удачного сохранения
    /// из `medication.doses` не убирает, и доза-призрак осталась бы
    /// видна экрану.
    @MainActor
    private static func отцепить(_ dose: DoseRecord, from context: ModelContext) {
        dose.medication = nil
        context.delete(dose)
    }

    /// Отметить дозу пропущенной.
    ///
    /// Пропуск — это запись, а не пустота. Врач спрашивает именно про
    /// него, а в истории иначе остаётся необъяснённая дыра: непонятно,
    /// забыли отметить или правда не дали.
    ///
    /// Возвращает отметку — или пусто, если записать не вышло. Пустой
    /// ответ экран обязан показать: «пропущено» без записи в истории —
    /// это та самая необъяснённая дыра, ради которой пропуск и заводили.
    @MainActor
    @discardableResult
    static func markSkipped(
        _ medication: Medication,
        scheduledAt scheduled: Date,
        by person: String,
        at now: Date = Date(),
        context: ModelContext
    ) -> DoseRecord? {
        let calendar = Calendar.current
        // На одну минуту бывает несколько отметок: у каждого телефона
        // общего дневника своя, с другим id. Данная любым из них — главнее
        // своей открытой, иначе чужое «дано» не остановило бы вторую дозу.
        let наМинуту = medication.doses.filter {
            calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
        }
        let существующая = наМинуту.first { $0.givenAt != nil } ?? наМинуту.first
        let dose = существующая ?? {
            let new = DoseRecord(scheduledAt: scheduled)
            new.medication = medication
            context.insert(new)
            return new
        }()

        guard dose.givenAt == nil else {
            UsageLog.note(.dose, "skipped", outcome: .blocked)
            return nil
        }
        dose.skippedAt = now
        dose.skippedBy = person
        guard context.persist(otherwise: {
            dose.skippedAt = nil
            dose.skippedBy = nil
            if существующая == nil { отцепить(dose, from: context) }
        }) else {
            UsageLog.note(.dose, "skipped", outcome: .failed)
            return nil
        }
        UsageLog.note(.dose, "skipped")
        return dose
    }

    /// Снять отметку с дозы.
    ///
    /// Отметили не ту или не тот человек — снять отметку должно быть можно.
    /// Иначе защита от двойной дозы работает против человека: она навсегда
    /// считает, что лекарство дано, и окно натощак отсчитывается от ошибки.
    ///
    /// Возвращает `false`, если снять не вышло: экран не должен говорить
    /// «снова в списке», пока доза в хранилище всё ещё отмечена. Иначе
    /// защита от двойной дозы молча остаётся включённой — человек уверен,
    /// что отметку снял, а лекарство второй раз дать нельзя.
    @MainActor
    @discardableResult
    static func unmark(
        _ medication: Medication,
        scheduledAt scheduled: Date,
        context: ModelContext
    ) -> Bool {
        let calendar = Calendar.current
        guard let dose = medication.doses.first(where: {
            calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
        // Отметки нет — снимать нечего, и это не отказ: цель достигнута.
        }) else { return true }

        let было = (dose.givenAt, dose.givenBy, dose.skippedAt, dose.skippedBy,
                    dose.claimedBy, dose.claimedAt, medication.stockLeft)

        // Отметку сняли — таблетка возвращается в пачку. Иначе счётчик
        // уезжал бы вниз на каждом промахе пальцем.
        if dose.givenAt != nil, medication.stockTotal > 0 {
            medication.stockLeft = min(medication.stockTotal, medication.stockLeft + 1)
        }

        dose.givenAt = nil
        dose.givenBy = nil
        dose.skippedAt = nil
        dose.skippedBy = nil
        // Заодно снимаем «беру на себя»: договорённость была про тот раз.
        dose.claimedBy = nil
        dose.claimedAt = nil
        guard context.persist(otherwise: {
            (dose.givenAt, dose.givenBy, dose.skippedAt, dose.skippedBy,
             dose.claimedBy, dose.claimedAt, medication.stockLeft) = было
        }) else {
            UsageLog.note(.dose, "unmarked", outcome: .failed)
            return false
        }
        UsageLog.note(.dose, "unmarked")
        return true
    }

    /// Окно натощак: когда снова можно кормить.
    ///
    /// Считается от фактической отметки, а не от расписания: таблетку дали
    /// в 07:12, а не в 07:00, и еда мешает всасыванию именно с этого момента.
    @MainActor
    static func fastingEnds(for dog: Dog, at now: Date = Date()) -> (until: Date, medication: String, givenAt: Date)? {
        guard dog.isOnTreatment else { return nil }

        for medication in dog.medications where medication.fastingMinutes > 0 && !medication.isPaused {
            guard let dose = medication.doses
                .filter({ $0.isGiven })
                .max(by: { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }),
                  let givenAt = dose.givenAt else { continue }

            let ends = givenAt.addingTimeInterval(Double(medication.fastingMinutes) * 60)
            if now < ends {
                return (until: ends, medication: medication.name, givenAt: givenAt)
            }
        }
        return nil
    }
}
