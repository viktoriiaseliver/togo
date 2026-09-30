import Foundation
import SwiftData

/// Такая же запись минуту назад — почти наверняка второй тап,
/// а не второе кормление.
///
/// **Почему отдельно от `EventLog`.** Правило жило внутри `EventLog`,
/// и защищён был ровно один путь — экранный. Запись голосом, кнопкой
/// «Действие» и ярлыком идёт мимо: `QuickLog.record` вставляет событие
/// и сохраняет, не спрашивая ни о правах, ни о дубле. То есть сказать
/// Siri «покорми» дважды подряд можно без всякой защиты, и человек
/// об этом не узнает: второй путь ещё и не пишет в журнал действий,
/// так что в замере его будто нет.
///
/// Замер 23.09.2026 по журналу с телефона: 112 записей, два дубля,
/// оба пойманы экранным путём (`record meal duplicate` через 6 и 8 секунд
/// после записи). Защита работает там, где она есть, — и её нет там,
/// где нажимают не глядя на экран, то есть где второй тап вероятнее всего.
@MainActor
enum DuplicateGuard {

    /// Насколько близко две одинаковые записи считаются одним тапом.
    ///
    /// Не выдумано: в живом дневнике нашлись три записи еды по 65 г
    /// с интервалом в две секунды — человек жал кнопку, не получая отклика,
    /// а потом удалял все три. Отклик починен, но защита нужна всё равно:
    /// палец соскакивает, и кнопку жмут дважды.
    static let window: TimeInterval = 90

    /// Виды записей, где два тапа подряд почти наверняка ошибка.
    ///
    /// С 30.09 сюда вошли стул, лакомство и выход: карточка быстрой
    /// записи обещает «два тапа подряд по одной кнопке — почти всегда
    /// промах, и приложение это ловит», а ловило только пять видов из
    /// восьми, что есть на кнопках. Два выхода за полторы минуты — это
    /// кнопка «Вывожу», нажатая дважды, а не две нужды.
    ///
    /// Повторяемое по смыслу сюда не входит. **Инцидент** — два подряд
    /// осмысленны: из них поднимается эпизод. Отметки прогулки (писал
    /// трижды за прогулку) дублем не считаются по связи с прогулкой —
    /// см. `refersToSameThing`.
    static let deduplicated: Set<LogKind> = [.meal, .walk, .care, .dose, .weight,
                                             .stool, .treat, .outing]

    /// Есть ли уже такая запись рядом по времени.
    ///
    /// Спрашиваем хранилище напрямую, а не связь `dog.events`. Связь
    /// применяется не мгновенно, и защита не срабатывала вовсе.
    static func recent(of kind: LogKind, dog: Dog, at date: Date,
                       like candidate: LogEvent, in context: ModelContext) -> LogEvent? {
        guard deduplicated.contains(kind) else { return nil }

        let raw = kind.rawValue
        let from = date.addingTimeInterval(-window)
        let till = date.addingTimeInterval(window)
        var descriptor = FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.kindRaw == raw && $0.date > from && $0.date < till },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30

        let dogID = dog.persistentModelID
        return (try? context.fetch(descriptor))?.first { existing in
            existing.deletedAt == nil
                && existing.dog?.persistentModelID == dogID
                && existing.persistentModelID != candidate.persistentModelID
                && refersToSameThing(existing, candidate)
        }
    }

    /// Две записи одного вида — это правда одно и то же?
    ///
    /// По виду судить мало. В живом дневнике две записи ухода стоят
    /// в секунде друг от друга — «Вычесать» и «Когти», — и это два разных
    /// дела, а не двойной тап. То же с препаратами: два лекарства в один
    /// час дают порознь и намеренно.
    ///
    /// Отметки прогулки — не тапы по кнопке, а то, что собака сделала:
    /// «писал» трижды за прогулку и стул сразу после выхода записываются
    /// честно. Строка с `walkEventID` не бывает дублем и не делает дублем
    /// других.
    static func refersToSameThing(_ lhs: LogEvent, _ rhs: LogEvent) -> Bool {
        guard lhs.walkEventID == nil, rhs.walkEventID == nil else { return false }
        switch lhs.kind {
        case .care: lhs.careTaskID == rhs.careTaskID
        case .dose: lhs.medicationID == rhs.medicationID
        default: true
        }
    }

    /// Что сказать человеку про найденный дубль.
    ///
    /// Без согласования по роду: «… уже записана» годилось для еды
    /// и прогулки, а с 30.09 сюда пришли «Выход» и «Стул» — через точку
    /// фраза читается одинаково для всех видов.
    static func message(_ kind: LogKind, at date: Date) -> String {
        String(localized: "\(kind.title) · уже записано в \(Fmt.clock(date))")
    }
}
