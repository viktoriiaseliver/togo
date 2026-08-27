import Foundation
import SwiftData

/// Общий дневник семьи.
///
/// Две вещи, которые здесь важнее скорости и красоты:
///
/// 1. **Отметку нельзя потерять.** Человек нажал «покормила» — запись
///    обязана дойти. Если два телефона спорят об одной записи, выигрывает
///    не «последний записавший», а тот, кто что-то **сделал**: отметка
///    приёма дозы, удаление, факт кормления.
/// 2. **Двойную дозу нельзя допустить.** Это единственное место
///    в приложении, где ошибка обмена — не путаница в дневнике,
///    а передозировка. Поэтому у дозы правило особое и жёсткое:
///    отметка «дано» побеждает всегда, с обеих сторон.
///
/// Слияние вынесено сюда целиком и работает на простых значениях,
/// а не на CloudKit: его можно проверить тестами, не имея двух телефонов.
nonisolated enum SharedDiary {
    /// Своя зона: только её и делят. Личные настройки телефона
    /// в общий дневник не попадают вовсе.
    static let zoneName = "family"

    /// Что синхронизируется.
    ///
    /// Список намеренно короткий: то, что двое правда делают вдвоём —
    /// отметки за день и приёмы препаратов. Профиль собаки, расписание
    /// ухода и занятия каждый ведёт у себя: их не заполняют в четыре
    /// руки, а фотографии сделали бы обмен тяжёлым ровно там, где он
    /// должен быть мгновенным.
    ///
    /// Виды ниже перечислены целиком, но обмениваются пока `event`
    /// и `dose` — и на экране написано именно это. Обещать больше, чем
    /// умеет обмен, дневнику с дозами нельзя.
    enum RecordType: String, CaseIterable, Sendable {
        case dog = "Dog"
        case event = "LogEvent"
        case care = "CareTask"
        case medication = "Medication"
        case dose = "DoseRecord"
        case weight = "WeightEntry"
        case member = "FamilyMember"
    }
}

// MARK: - Что кладём в запись

/// Снимок записи для обмена: обычные значения, без CloudKit.
///
/// Отдельный тип, а не словарь: у словаря нельзя проверить тестом,
/// что поле не потерялось при переименовании.
nonisolated struct EventPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var kind: String
    var date: Date
    var authorName: String
    var note: String?

    var outcome: String?
    var durationSeconds: Int?
    var stoolForm: String?
    var stoolFlags: [String]
    var grams: Int?
    var milliliters: Int?
    var fromPortion: Bool
    var incidentKind: String?
    var incidentDetail: String?
    var walkEventID: UUID?
    var careTaskID: UUID?
    var medicationID: UUID?

    var deletedAt: Date?
    var deletedBy: String?

    /// Когда телефон в последний раз трогал эту запись.
    ///
    /// Нужно для спора о правке: у двоих может быть разное представление
    /// о граммах, и выигрывать должен тот, кто правил позже.
    var changedAt: Date
}

/// Отметка приёма препарата.
nonisolated struct DosePayload: Equatable, Sendable, Codable {
    var id: UUID
    var medicationID: UUID?
    var scheduledAt: Date
    var givenAt: Date?
    var givenBy: String?
    var skippedAt: Date?
    var skippedBy: String?
    var claimedBy: String?
    var claimedAt: Date?
    var cancelledAt: Date?
    var cancelReason: String?
    var changedAt: Date
}

// MARK: - Кто выигрывает спор

nonisolated enum SharedDiaryMerge {

    /// Спор о записи дневника.
    ///
    /// Правила по убыванию силы:
    ///
    /// 1. **Удаление сильнее правки.** Если один удалил, а другой в это же
    ///    время поправил заметку — запись удалена. Вернуть удалённое стоит
    ///    один тап, а вот «я удалила, а оно вернулось» — это потеря доверия
    ///    к дневнику целиком.
    /// 2. **Позже — значит вернее.** В остальном выигрывает тот, кто
    ///    трогал запись последним.
    /// 3. **При равном времени выигрывает не пустое.** Часы на двух
    ///    телефонах расходятся на секунды, и при ничьей разумнее взять
    ///    ту версию, где данных больше, чем ту, где их стёрли.
    static func resolve(local: EventPayload, remote: EventPayload) -> EventPayload {
        precondition(local.id == remote.id)

        // Удаление не отменяется чужой правкой — только явным возвратом.
        if local.deletedAt != nil, remote.deletedAt == nil, remote.changedAt <= local.changedAt {
            return local
        }
        if remote.deletedAt != nil, local.deletedAt == nil, local.changedAt <= remote.changedAt {
            return remote
        }

        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }

        return filledFields(local) >= filledFields(remote) ? local : remote
    }

    /// Спор об отметке дозы.
    ///
    /// Здесь правило одно и оно сильнее всех остальных: **если хотя бы
    /// один телефон считает, что доза дана — доза дана.** Двое, дающие
    /// дозу порознь, это не путаница в дневнике, а передозировка;
    /// и лучше показать лишний замок, чем позволить дать вторую таблетку.
    ///
    /// Раньше «дано» побеждало и время: из двух отметок берётся более
    /// ранняя — от неё считается окно натощак, и ошибаться в эту сторону
    /// безопаснее.
    static func resolve(local: DosePayload, remote: DosePayload) -> DosePayload {
        precondition(local.id == remote.id)

        var winner = local.changedAt >= remote.changedAt ? local : remote

        // Отметка «дано» не теряется ни при каких обстоятельствах.
        let givenSides = [local, remote].filter { $0.givenAt != nil }
        if let earliest = givenSides.min(by: { ($0.givenAt ?? .distantFuture) < ($1.givenAt ?? .distantFuture) }) {
            winner.givenAt = earliest.givenAt
            winner.givenBy = earliest.givenBy
            // Дали — значит не пропустили.
            winner.skippedAt = nil
            winner.skippedBy = nil
            return winner
        }

        // Пропуск — тоже решение человека, и стирать его чужой тишиной
        // нельзя.
        if let skipped = [local, remote].first(where: { $0.skippedAt != nil }) {
            winner.skippedAt = skipped.skippedAt
            winner.skippedBy = skipped.skippedBy
        }

        // «Беру на себя» держится тем, кто взял раньше: иначе двое
        // перехватывают дозу друг у друга по кругу.
        let claims = [local, remote].filter { $0.claimedAt != nil }
        if let first = claims.min(by: { ($0.claimedAt ?? .distantFuture) < ($1.claimedAt ?? .distantFuture) }) {
            winner.claimedBy = first.claimedBy
            winner.claimedAt = first.claimedAt
        }

        return winner
    }

    /// Насколько версия заполнена. Считается только то, что человек
    /// вводит руками: у автоматических полей значение есть всегда.
    private static func filledFields(_ payload: EventPayload) -> Int {
        var count = 0
        if payload.note?.isEmpty == false { count += 1 }
        if payload.outcome != nil { count += 1 }
        if payload.durationSeconds != nil { count += 1 }
        if payload.stoolForm != nil { count += 1 }
        if !payload.stoolFlags.isEmpty { count += 1 }
        if payload.grams != nil { count += 1 }
        if payload.milliliters != nil { count += 1 }
        if payload.incidentKind != nil { count += 1 }
        if payload.incidentDetail != nil { count += 1 }
        return count
    }
}
