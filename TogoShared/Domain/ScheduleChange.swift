import Foundation
import SwiftData

/// Смена схемы после приёма у врача.
///
/// Из хендофа (17c): «Старое и новое рядом, перечёркнуто только старое.
/// Вопрос „с какого момента“ задан явно — это место, где семьи чаще
/// всего ошибаются в первый день новой схемы».
///
/// Главное правило: **прошлые отметки не трогаем.** Меняется только план
/// вперёд. Иначе история приёмов задним числом станет неправдой — а её
/// потом читает тот же врач.
nonisolated struct ScheduleChange: Equatable, Sendable {
    /// С какого момента действует новое.
    enum StartsFrom: String, CaseIterable, Sendable {
        case tomorrowMorning
        case tonight

        var title: String {
            switch self {
            case .tomorrowMorning: String(localized: "С завтрашнего утра")
            case .tonight: String(localized: "Сегодня вечером")
            }
        }
    }

    var oldDoseText: String
    var oldTimes: [Int]
    var newDoseText: String
    var newTimes: [Int]
    var startsFrom: StartsFrom

    /// «дважды в день» / «один раз · утром».
    static func summary(_ times: [Int]) -> String {
        let sorted = times.sorted()
        switch sorted.count {
        case 0: return String(localized: "без расписания")
        case 1:
            let hour = sorted[0] / 60
            let when = hour < 12 ? String(localized: "утром") : (hour < 17 ? String(localized: "днём") : String(localized: "вечером"))
            return String(localized: "один раз · \(when)")
        case 2: return String(localized: "дважды в день")
        default: return "\(String(localized: "\(sorted.count) раз")) в день"
        }
    }

    /// С какого момента новое расписание вступает в силу.
    func effectiveFrom(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch startsFrom {
        case .tonight:
            return now
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            return tomorrow ?? now
        }
    }

    /// Какие уже заведённые отметки уйдут из плана.
    ///
    /// Считается заранее и показывается до нажатия: «Вечернее в 20:00
    /// отменится» — не сюрприз после сохранения.
    ///
    /// **Уже отменённые сюда не попадают, и это не косметика.** С тех
    /// пор как отмена оставляет запись (см. `ScheduleChangeApplier`),
    /// доза с `cancelledAt` остаётся в базе навсегда — а без этого
    /// условия каждая следующая правка схемы показывала бы её человеку
    /// снова, обещая отменить отменённое, и переписывала бы дату
    /// и причину первой отмены на свои. То есть запись об отмене
    /// теряла бы ровно то, ради чего её заводили: **когда и почему**.
    func doomedDoses(_ doses: [DoseRecord], now: Date = Date(),
                     calendar: Calendar = .current) -> [DoseRecord] {
        let from = effectiveFrom(now: now, calendar: calendar)
        let keep = Set(newTimes)
        return doses.filter { dose in
            guard dose.scheduledAt >= from, !dose.isGiven, !dose.isSkipped,
                  dose.cancelledAt == nil else { return false }
            let minute = calendar.component(.hour, from: dose.scheduledAt) * 60
                + calendar.component(.minute, from: dose.scheduledAt)
            return !keep.contains(minute)
        }
    }
}

/// Отмена дозы — **единственное место, где пишется `cancelledAt`**
/// по решению человека.
///
/// # Чем отмена отличается от пропуска, и почему это не второй
/// механизм на тот же смысл
///
/// Разница не в слове, а в том, кто и о чём решил, и видна она
/// в отчёте врачу:
///
/// ```
/// skippedAt/skippedBy  человек решил НЕ ДАТЬ назначенную дозу.
///                      У решения есть автор, и оно считается:
///                      VetSummaryScreen печатает «Пропущено
///                      осознанно: N» (`:105`), CourseFinishSheet
///                      тоже (`:65`)
/// cancelledAt/         дозу БОЛЬШЕ НЕ НАДО ДАВАТЬ: план изменился.
/// cancelReason         Автора нет и поля под него нет — решение
///                      не о том, дали ли лекарство, а о том, что
///                      его перестали назначать
/// ```
///
/// Склеить их значило бы записать в отчёт, что хозяйка пропустила дозы,
/// которых ей никто не назначал: врач читает `dosesSkipped` как недобор
/// лечения. Поэтому поля два, и смысл у них разный.
///
/// > **Поэтому отдельной кнопки «отменить эту дозу» рядом
/// > с «пропустить» НЕТ, и это решение, а не недоделка.** Человеку
/// > пришлось бы выбирать между двумя кнопками, разница которых —
/// > «попадёт ли это в отчёт врачу как пропуск». Такой выбор он сделает
/// > неверно, и ошибку не заметит никто. Отмена дозы — следствие правки
/// > плана, и приходит она оттуда.
///
/// # Почему здесь нет своего `save`, в отличие от `markSkipped`
///
/// Отмена дозы **никогда не бывает одиночной правкой**: её всегда
/// сопровождает то, из-за чего план изменился — новые часы схемы,
/// конец курса. Своё сохранение внутри дало бы два `save` на одно
/// решение и щель между ними, в которой дозы уже отменены, а расписание
/// ещё старое. Поэтому функция только помечает и возвращает откат;
/// сохраняет и откатывает вызывающий, одной транзакцией со своей
/// половиной правки.
///
/// # Почему тип лежит здесь, а не рядом с `markGiven`/`markSkipped`
///
/// **Причина честная и не архитектурная: `DoseScheduler.swift` 26.10
/// держала другая сессия со своей незакоммиченной правкой**, а поимённый
/// коммит берёт файл целиком. Положить отмену туда значило бы либо унести
/// чужую незавершённую работу, либо не закоммитить свою вовсе.
///
/// Место при этом не случайное: оба будущих вызывающих — правки ПЛАНА
/// (`ScheduleChangeApplier` ниже, `TreatmentCourse.finish`), а не отметки
/// приёма, и «мутация плюс откат, сохраняет вызывающий» — это форма
/// строительного блока, а не кнопки. Переносить обратно к отметкам можно,
/// **но только целиком**: ценность здесь в том, что писатель `cancelledAt`
/// ОДИН, а не в том, в каком файле он лежит.
nonisolated enum ОтменаДозы {
    /// Уже отменённые, отмеченные и пропущенные не трогаются: отмена
    /// не переписывает чужое решение и не продлевает своё повторным
    /// заходом — иначе вторая правка схемы затёрла бы дату и причину
    /// первой отмены.
    ///
    /// «Беру на себя» снимается: договорённость была про дозу, которой
    /// больше нет в плане. Пара `claimedBy`/`claimedAt` снимается
    /// целиком — как у `DoseScheduler.unmark` и по той же причине:
    /// половина пары опаснее целой.
    @MainActor
    static func пометить(
        _ doses: [DoseRecord],
        reason: String,
        at now: Date = Date()
    ) -> (count: Int, undo: () -> Void) {
        let цель = doses.filter {
            $0.cancelledAt == nil && $0.givenAt == nil && $0.skippedAt == nil
        }
        let было = цель.map { ($0.cancelledAt, $0.cancelReason, $0.claimedBy, $0.claimedAt) }
        for dose in цель {
            dose.cancelledAt = now
            dose.cancelReason = reason
            dose.claimedBy = nil
            dose.claimedAt = nil
        }
        return (цель.count, {
            for (dose, снимок) in zip(цель, было) {
                (dose.cancelledAt, dose.cancelReason, dose.claimedBy, dose.claimedAt) = снимок
            }
        })
    }
}

nonisolated enum ScheduleChangeApplier {
    /// Применить новую схему.
    ///
    /// Возвращает, сколько будущих отметок отменено, — это надо сказать
    /// человеку теми же словами, какими его предупреждали.
    ///
    /// # Отмена вместо удаления — замер 26.10.2026
    ///
    /// До этой правки будущие отметки сносились `context.delete`.
    /// Модель обещает обратное прямым текстом: «Отмена дозы оставляет
    /// запись об отмене, а не стирает её» (`DoseRecord.cancelledAt`).
    /// Поля `cancelledAt` и `cancelReason` есть с самого начала, их
    /// читают ворота планировщика (`DoseScheduler.removeOrphans`),
    /// `ждётОтметки`, `escalationStage` и спор телефонов
    /// (`SharedDiaryMerge.resolve`) — **писал их только приём извне
    /// и откат архива.** То есть механизм учитывал отмену, совершить
    /// которую было нечем, а единственная дорога от человека,
    /// означающая ровно отмену, записи не оставляла.
    ///
    /// **Жёсткое удаление здесь стоило дороже записи в истории.**
    /// Исходящая очередь собирается из `ModelContext.didSave`,
    /// а удалённая запись не приходит ни в `inserted`, ни в `updated`
    /// (разбор — `Medication.deletedAt`): до второго телефона снос
    /// не доезжал **вовсе**. У мамы доза оставалась живой. Отмена
    /// едет обычной правкой: `cancelledAt` и `cancelReason` уже
    /// в полезной нагрузке (`SharedDiaryPayloads`), а спор решается
    /// `local.cancelledAt ?? remote.cancelledAt` — отмена липкая,
    /// то есть выбрана безопасная сторона «не дать отменённую
    /// таблетку».
    ///
    /// **Показа это не ломает, и это замер, а не расчёт.** План дня
    /// строится из `medication.times`, а не из отметок
    /// (`DayPlanBuilder:58`), поэтому отмененная доза на час, которого
    /// в расписании больше нет, в план не попадает. `removeOrphans`
    /// её не сметёт (`cancelledAt == nil` в его `guard`), `ensureDoses`
    /// не заведёт заново (минуты нет в `times`), эскалация молчит
    /// (`escalationStage` отдаёт 0), напоминания снимаются
    /// (`ждётОтметки` ложно).
    ///
    /// **Чего эта правка НЕ делает.** Шторка, из которой человек сюда
    /// попадает, по-прежнему говорит «20:00 удалится» и рисует корзину
    /// (`ScheduleChangeSheet:155,157`). Слово разошлось с делом, и
    /// исправить его здесь нельзя: файл держит другая сессия. Названо
    /// вслух и отдано менеджеру — **предупреждение о расхождении живёт
    /// рядом с предметом, а не только в наряде.**
    ///
    /// Второй путь, означающий ровно отмену, — `TreatmentCourse.finish`
    /// (`:53-58`), и он тоже сносит будущие дозы `context.delete`.
    /// Файл не мой; дефект тот же, починка та же.
    @MainActor
    @discardableResult
    static func apply(
        _ change: ScheduleChange,
        to medication: Medication,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) -> Int? {
        let doomed = change.doomedDoses(medication.doses, now: now, calendar: calendar)
        // Причина записывается словами человека, а не кодом состояния:
        // её читает тот, кто через месяц разбирает историю приёмов
        // вместе с врачом. Форма — та же, что у отмены схемы
        // (`Medication.отменить`: «Курс завершён <дата>»), чтобы две
        // отмены в одной истории читались одинаково.
        let отмена = ОтменаДозы.пометить(
            doomed,
            reason: String(localized: "Схема изменена \(Fmt.shortDay(now))"),
            at: now)

        // Прошлое остаётся как было: меняется только план вперёд.
        let былДоза = medication.doseText
        let былиЧасы = medication.times
        medication.doseText = change.newDoseText
        medication.times = change.newTimes.sorted()
        // Схема лечения — место, где молчание стоит дозы: экран покажет
        // новые часы, а напоминания придут по старым.
        //
        // Отмена дозы и новые часы — **одна транзакция**. Два `save`
        // оставили бы щель, в которой дозы уже отменены, а расписание
        // ещё старое: ровно то состояние, из которого `ensureDoses`
        // завела бы отмену и новую отметку на один час.
        guard context.persist(otherwise: {
            medication.doseText = былДоза
            medication.times = былиЧасы
            отмена.undo()
        }) else { return nil }
        return отмена.count
    }
}
