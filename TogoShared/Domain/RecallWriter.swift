import Foundation
import SwiftData

/// Запись дозаписи в дневник.
///
/// Разбор (`RecallParser`) текст только понимает. Класть в базу — сюда,
/// и это намеренно два разных места: разбор проверяется тестами без
/// хранилища, а запись обязана считаться с правами, дублями
/// и происхождением.
///
/// **Ничего не пишется без подтверждения человека.** На вход идут
/// черновики, которые он уже увидел списком и поправил: снял лишние дни,
/// подвинул даты, дописал словами. `RecallWriter` не разбирает текст
/// и не угадывает — он только сохраняет согласованное.
nonisolated enum RecallWriter {

    /// Что получилось записать.
    public struct Outcome: Equatable {
        public var written: Int
        public var skipped: Int
        /// Дни, которые уже есть в дневнике: второй раз их не пишем.
        public var duplicates: [Date]
    }

    /// Записать подтверждённые дни.
    ///
    /// - Parameters:
    ///   - drafts: черновики после правки человеком.
    ///   - origin: `.parsed`, если пришло из текста, `.recalled` — если
    ///     человек завёл дни руками. Врач разницы не увидит, приложение —
    ///     обязано.
    @MainActor
    @discardableResult
    static func write(
        _ drafts: [RecallParser.DayDraft],
        for dog: Dog,
        author: String,
        origin: RecordOrigin,
        existing: [LogEvent],
        context: ModelContext
    ) -> Outcome {
        let calendar = Calendar.current
        var written = 0, skipped = 0
        var duplicates: [Date] = []

        for draft in drafts {
            guard !draft.isExcluded else { skipped += 1; continue }

            // Дубль — это уже записанный **день того же вида**. Час здесь
            // не сравниваем: у дозаписи его нет, и сравнивать было бы
            // нечем. Без этой проверки повторный разбор того же письма
            // удвоил бы две недели истории.
            let alreadyThere = existing.contains { event in
                event.kindRaw == draft.kind.rawValue
                    && calendar.isDate(event.date, inSameDayAs: draft.day)
                    && event.isDayOnly
            }
            if alreadyThere {
                duplicates.append(draft.day)
                skipped += 1
                continue
            }

            let event = LogEvent(kind: draft.kind, date: draft.day, authorName: author)
            event.dog = dog
            event.origin = origin
            event.enteredAt = Date()
            // Час неизвестен — и это записано полем, а не подставлено
            // полуднем. Полдень выглядел бы измерением.
            event.isDayOnly = true
            event.note = draft.note
            if let seconds = draft.durationSeconds { event.durationSeconds = seconds }
            context.insert(event)
            written += 1
        }

        if written > 0 { try? context.save() }
        return Outcome(written: written, skipped: skipped, duplicates: duplicates)
    }

    /// Строка для выгрузки врачу.
    ///
    /// Требование заказчицы: в теле выгрузки дозапись **не отличается**
    /// от истории — врач читает одну таблицу, а не две. Но врач принимает
    /// решения по этим данным, и «понос 13 сентября» по памяти —
    /// свидетельство другой силы, чем отметка в 14:02.
    ///
    /// Компромисс: пометок у строк нет, а в конце документа — одна строка
    /// числом. Без разбивки, без указания каких именно записей.
    /// Пусто, если по памяти не внесено ничего.
    static func footnote(for events: [LogEvent]) -> String? {
        let recalled = events.filter(\.isRecalled).count
        guard recalled > 0 else { return nil }
        return "\(Fmt.plural(recalled, "запись внесена", "записи внесены", "записей внесены")) "
            + "по памяти, из \(events.count)"
    }
}
