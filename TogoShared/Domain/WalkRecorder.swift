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
    ) -> LogEvent? {
        var вставленные: [LogEvent] = []
        let walk = LogEvent(kind: .walk, date: session.startedAt, authorName: author)
        // Конец — момент «Домой» на блокировке, если прогулку закончили
        // там. Записывает её приложение позже, при открытии, и `Date()`
        // здесь прибавлял к прогулке всё время, пока телефон лежал
        // в кармане: закончили в 10:00, открыли в 11:30 — полтора часа
        // лишних (аудит 28.10.2026). Эту длительность читает сводка врачу.
        walk.durationSeconds = Int(session.duration(at: session.закончиласьНаБлокировке ?? Date()))
        walk.dog = dog
        context.insert(walk)
        вставленные.append(walk)

        var принятые: [ActiveSession.Mark] = []
        for mark in session.marks {
            let event = LogEvent(kind: mark.kind.logKind, date: mark.at, authorName: author)
            apply(mark, to: event, dog: dog, walkID: walk.id)

            // Два тапа по одной кнопке. До 07.10.2026 этот путь
            // не спрашивал `DuplicateGuard` вовсе — ни про `.outing`,
            // которого в наборе не было, ни про `.walk`, который в наборе
            // с 23.09. Замер по журналу действий нашёл три отметки мочи
            // в 19:50:24, :26 и :27 одной прогулки и ещё две в 06:09:58
            // и :59 другой — а настоящие повторы того же дня стоят
            // в 36, 131 и 213 секундах.
            //
            // Сначала пачка, потом хранилище: отметки одной прогулки
            // вставляются до `save`, и `recent` их не ищет. Все пять
            // измеренных дублей лежали внутри пачки — только через
            // хранилище покрытие не достало бы ни до одного.
            if вставленные.contains(where: { DuplicateGuard.isDuplicate($0, event) })
                || DuplicateGuard.recent(of: event.kind, dog: dog, at: event.date,
                                         like: event, in: context) != nil {
                // Молча не роняем: без этой строки путь не отличить
                // в замере от того, где дублей не бывает.
                UsageLog.note(.record, event.kind.rawValue, outcome: .duplicate)
                continue
            }

            event.dog = dog
            context.insert(event)
            вставленные.append(event)
            принятые.append(mark)
        }

        // Сводка — по принятым отметкам, а не по тапам.
        //
        // Иначе подпись прогулки говорит «пописал ×3» над одной записью,
        // и расхождение читается как потеря записей. В живом дневнике
        // эта пара стоит рядом и ровно так и выглядит: `пописал ×3`
        // и три строки под ним, из которых настоящая одна.
        walk.note = принятые.isEmpty ? nil : {
            var итог = session
            итог.marks = принятые
            return итог.tally
        }()

        // Прогулка с отметками — самая дорогая запись дня: человек
        // отмечал её двадцать минут. Не сохранилось — возвращаем
        // вставленное и отвечаем `nil`, чтобы экран не показал успех.
        guard context.persist(otherwise: { вставленные.forEach(context.delete) }) else {
            return nil
        }
        return walk
    }
}
