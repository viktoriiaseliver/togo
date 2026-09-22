import Foundation
import CloudKit

/// Серверные версии записей, которые мы отправляли.
///
/// **Почему без этого терялось каждое второе сохранение.** CloudKit
/// принимает правку записи, только если в ней стоит тот же
/// `recordChangeTag`, что лежит на сервере. Прежде каждая отправка
/// собирала НОВЫЙ `CKRecord` — без тега вовсе. Первое сохранение
/// проходило (записи на сервере ещё нет), а второе — «дано», правка
/// граммов, удаление — падало на `serverRecordChanged` и больше
/// не повторялось: в журнал уходила строка, и на этом всё. До второго
/// телефона доезжала только самая первая версия записи, а отметка
/// приёма дозы не доезжала никогда.
///
/// Тег сервера взять неоткуда, кроме как с самого сервера. Поэтому
/// здесь лежат три источника одного и того же: записи, которые сервер
/// подтвердил, записи, которые он прислал, и записи из ошибки спора.
@MainActor
final class SharedDiaryOutbox {

    private var known: [CKRecord.ID: CKRecord] = [:]

    /// Серверная версия, поверх которой надо слать свою правку.
    func base(for id: CKRecord.ID) -> CKRecord? { known[id] }

    func remember(_ record: CKRecord) { known[record.recordID] = record }

    func remember(_ records: [CKRecord]) {
        for record in records { remember(record) }
    }

    /// Запись больше не наша забота — или её тег заведомо протух.
    func forget(_ id: CKRecord.ID) { known[id] = nil }

    func forgetAll() { known.removeAll() }

    /// Разобрать неудавшиеся отправки.
    ///
    /// Возвращает записи, которые надо поставить в очередь заново.
    /// Спор о версии — это не отказ, а «возьми свежую и пришли ещё
    /// раз»; молча потерять отметку здесь нельзя, ради неё весь обмен
    /// и затевался.
    func retries(after failures: [(id: CKRecord.ID, error: Error)]) -> [CKRecord.ID] {
        var again: [CKRecord.ID] = []

        for failure in failures {
            // Через `NSError`, а не через `as? CKError`: тот же разбор
            // работает и для ошибки, собранной в тесте, — CloudKit
            // в тест не поставить вовсе.
            let raw = failure.error as NSError
            guard raw.domain == CKErrorDomain,
                  let code = CKError.Code(rawValue: raw.code)
            else { continue }

            switch code {
            case .serverRecordChanged:
                // Сервер прислал свою версию — с ней и пойдём во второй раз.
                if let server = raw.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    remember(server)
                }
                again.append(failure.id)

            case .unknownItem:
                // На сервере записи нет: наш тег указывает в пустоту.
                // Шлём заново, с чистого листа.
                forget(failure.id)
                again.append(failure.id)

            case .zoneNotFound, .userDeletedZone:
                // Зоны нет — теги всех записей бессмысленны. Повторять
                // нечего: зону пересоздаёт движок, а не мы.
                forgetAll()

            default:
                continue
            }
        }

        return again
    }
}
