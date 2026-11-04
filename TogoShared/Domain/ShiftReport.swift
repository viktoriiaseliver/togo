import Foundation

/// Собрать итог смены из того, что уже записано.
///
/// План дня и лента — один и тот же материал, просто нарезанный по часам
/// дежурства. Своего учёта смена не ведёт: он бы разошёлся с дневником
/// на второй же день.
nonisolated enum ShiftReport {

    /// Пункт плана глазами отчёта: что это, к чему привязан и кто
    /// его закрыл, если это известно прямо.
    ///
    /// # Почему не кортеж `(id, title, due, isDone)`, как было
    ///
    /// До 29.10.2026 автор пункта искался как «ближайшая по времени
    /// запись смены» — **любого вида**. Доза в 08:00 закрывалась
    /// выходом в 08:02, и в итоге смены стояло «дала Аня» за таблетку,
    /// которую дал Игорь: Аня в ту минуту вывела собаку. Уход стоит
    /// в плане на час сна (`DayPlanBuilder`, «у него нет часа»),
    /// отмечают его днём — и автором становился тот, кто вечером
    /// кормил, либо никто.
    ///
    /// > **«Кто закрыл» — это утверждение о человеке, и отчёт читают
    /// > на локскрине как факт.** Приписать дозу не тому значит
    /// > ответить «дали» на вопрос, на который надо было переспросить.
    ///
    /// Поэтому пункт несёт то, по чему его запись узнаётся: вид записи
    /// и связь (`medicationID` у дозы, `careTaskID` у ухода), а у дозы —
    /// ещё и автора из самой отметки (`DoseRecord.givenBy`), если он
    /// есть: он сильнее любой записи ленты.
    struct Пункт {
        var id: String
        var title: String
        var due: Date
        var isDone: Bool
        /// Каким видом записи этот пункт закрывают.
        var вид: LogKind
        /// Схема у дозы, дело у ухода. `nil` — привязки нет (еда).
        var связь: UUID? = nil
        /// Кто закрыл, если это записано в самой отметке.
        var автор: String? = nil
        /// Какая запись закрыла пункт, если это уже известно сборщику
        /// плана.
        ///
        /// **Заведено 04.11.2026 вместо второго поиска по ленте.**
        /// Ниже лежал `автор(для:среди:)` с собственным допуском
        /// ±`MealSchedule.doneTolerance` — вторая копия правила
        /// «эта запись закрывает этот слот», и расходиться с первой
        /// она начала на записи вне слота: план считал пункт
        /// закрытым, а итог смены отвечал «автора нет» при известном
        /// авторе.
        var записьID: UUID? = nil
    }

    /// - Parameters:
    ///   - plan: пункты режима дня со временем, признаком выполнения
    ///     и тем, по чему узнаётся их запись.
    ///   - events: записи дневника — из них берётся, кто закрыл пункт,
    ///     когда в самом пункте автора нет.
    @MainActor
    static func build(
        shift: Shift,
        plan: [Пункт],
        events: [LogEvent],
        tolerance: TimeInterval = MealSchedule.потолокЗакрытия,
        calendar: Calendar = .current
    ) -> ShiftSummary {
        let смены = Diary.active(events).filter { shift.covers($0.date) }

        let items = plan
            .filter { shift.covers($0.due) }
            .map { entry in
                let author = entry.isDone
                    ? (Fmt.notBlank(entry.автор ?? "") ?? автор(для: entry, среди: смены,
                                                               tolerance: tolerance, calendar: calendar))
                    : nil
                return ShiftItem(id: entry.id, title: entry.title, due: entry.due,
                                 isDone: entry.isDone, by: author)
            }
            .sorted { $0.due < $1.due }

        return ShiftSummary(shift: shift, items: items)
    }

    /// Автор — у записи ТОГО ЖЕ вида и с той же связью.
    ///
    /// Нашлось несколько — берётся ближайшая ко сроку. Связанного ухода
    /// это не касается: у него нет часа, и окно `tolerance` вокруг
    /// часа сна отбросило бы дневную отметку; поэтому уход ищется
    /// в тот же день, последняя запись. Не нашлось — `nil`: «закрыто,
    /// а кем — не записано» честнее, чем имя соседа по минуте.
    @MainActor
    private static func автор(для entry: Пункт, среди события: [LogEvent],
                              tolerance: TimeInterval, calendar: Calendar) -> String? {
        let подходящие = события.filter { событие in
            guard событие.kind == entry.вид else { return false }
            guard let связь = entry.связь else { return true }
            switch entry.вид {
            case .dose: return событие.medicationID == связь
            case .care: return событие.careTaskID == связь
            default: return true
            }
        }
        let найдено: LogEvent?
        // Сборщик плана уже назвал запись — второй раз её не ищем.
        // Этот путь существует для доз и ухода, у которых связь
        // идёт по схеме и делу, а не по идентификатору записи.
        if let id = entry.записьID {
            найдено = подходящие.first { $0.id == id }
        } else if entry.вид == .care, entry.связь != nil {
            найдено = подходящие
                .filter { calendar.isDate($0.date, inSameDayAs: entry.due) }
                .max { $0.date < $1.date }
        } else {
            найдено = подходящие
                .filter { abs($0.date.timeIntervalSince(entry.due)) <= tolerance }
                .min { abs($0.date.timeIntervalSince(entry.due))
                     < abs($1.date.timeIntervalSince(entry.due)) }
        }
        return найдено.flatMap { Fmt.notBlank($0.authorName) }
    }
}
