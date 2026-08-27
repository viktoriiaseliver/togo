import Foundation
import SwiftData

/// Как отметка прогулки превращается в запись дневника.
///
/// Одно место на два пути: экран прогулки и метка у двери. Пока правило
/// было переписано в каждом из них своими словами, они расходились —
/// и лакомство с прогулки, записанное голосом, не попадало в подсчёт
/// питания, хотя то же лакомство с экрана попадало.
nonisolated enum WalkRecorder {

    /// Заполнить запись по отметке прогулки.
    @MainActor
    static func apply(_ mark: ActiveSession.Mark, to event: LogEvent, dog: Dog, walkID: UUID?) {
        // Настоящая связь, а не подпись словами: по ней лента собирает
        // прогулку обратно в одно событие.
        event.walkEventID = walkID
        switch mark.kind {
        case .urine: event.outcome = .urine
        case .stool: event.stoolForm = Diary.usualStool(dog.events)
        case .treat:
            event.grams = 5
            // Без этого пять граммов исчезали из подсчёта питания: сводка
            // считает лакомствами только то, что взято из дневной порции.
            event.fromPortion = dog.trainingFoodFromPortion
        default: break
        }
        event.note = "на прогулке"
    }

    /// Записать законченную прогулку целиком.
    ///
    /// Нужен там, где нет экрана: метка у двери, «Команды», Siri.
    /// Возвращает саму запись прогулки.
    @MainActor
    @discardableResult
    static func record(
        _ session: ActiveSession,
        dog: Dog,
        author: String,
        context: ModelContext
    ) -> LogEvent {
        let walk = LogEvent(kind: .walk, date: session.startedAt, authorName: author)
        walk.durationSeconds = Int(session.duration())
        walk.note = session.marks.isEmpty ? nil : session.tally
        walk.dog = dog
        context.insert(walk)

        for mark in session.marks {
            let event = LogEvent(kind: mark.kind.logKind, date: mark.at, authorName: author)
            apply(mark, to: event, dog: dog, walkID: walk.id)
            event.dog = dog
            context.insert(event)
        }

        try? context.save()
        return walk
    }
}
