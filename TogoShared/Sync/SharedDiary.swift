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

/// Профиль собаки.
///
/// **Зачем он ездит.** Хозяйка пригласила маму со-владельцем и написала
/// в тот же вечер дважды: «у неё нет половины функционала» и «мама
/// не видит то же, что и я, и не видит мою собаку». Причина была одна:
/// общая зона возила два типа записей из семи, и собаки среди них
/// не было. Приглашение работало и приводило в пустую комнату.
///
/// **Чего здесь нет и почему.**
///
/// - `photo` — решение брифа 22.09: снимки сделали бы обмен тяжёлым
///   ровно там, где он должен быть мгновенным. Фото каждый ставит у себя.
/// - Заметки для ситтера (`sitterFood` и соседние) — их пишет тот, кто
///   уезжает, под конкретную поездку; общими они не бывают.
/// - `createdAt` — это факт про ЧУЖОЙ телефон, и на нашем он значил бы
///   не то. Когда собака появилась здесь, помнит `DogOrigin`.
nonisolated struct DogPayload: Equatable, Sendable, Codable {
    var id: UUID
    var name: String
    var breed: String?
    var birthDate: Date?
    var sex: String
    var isNeutered: Bool
    var weightKg: Double
    var targetWeightLow: Double?
    var targetWeightHigh: Double?

    var foodBrand: String
    var portionGrams: Int
    var mealsPerDay: Int
    var mealTimes: [Int]
    var dailyNormGrams: Int?
    var forbiddenFoods: [String]

    var wakeMinuteOfDay: Int
    var sleepMinuteOfDay: Int

    /// Лечение идёт — от этого зависит, видна ли вкладка «Здоровье».
    /// Без него у гостя она скрыта, и приёмы, которые он же отмечает,
    /// показывать негде.
    var isOnTreatment: Bool

    /// Документы и врач: то, что нужно второму человеку, когда он один
    /// с собакой и что-то случилось.
    var chipNumber: String?
    var vetName: String?
    var vetPhone: String?
    var clinicName: String?
    var clinicPhone: String?
    var distinctiveMarks: String?

    var changedAt: Date
}

/// Отметка приёма препарата.
nonisolated struct DosePayload: Equatable, Sendable, Codable {
    var id: UUID
    var medicationID: UUID?

    /// Как препарат называется — на случай, когда id не подошёл.
    ///
    /// Схемы лечения не обмениваются (`RecordType` выше: ездят только
    /// `event` и `dose`), и это не недоделка, а решение: схему заводит
    /// владелец, у второго человека тот же препарат заведён своей рукой
    /// и с другим UUID. Значит, промах по id — обычное дело, а не сбой.
    /// Пока связи по имени не было, чужая отметка «дано» ложилась
    /// на дозу без препарата и на экране не появлялась: мама отмечала
    /// приём, муж видел открытую дозу — и давал вторую таблетку.
    var medicationName: String?

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

    /// Спор о профиле собаки.
    ///
    /// Решение Виктории от 23.09.2026: **побеждает правка, что позже.**
    /// У ленты правила сложнее («удаление сильнее правки», «дано»
    /// побеждает всегда), и это оправдано ценой ошибки — там
    /// передозировка. У профиля такой цены нет: вес и порция это факты,
    /// которые уточняют, а не решения, которые отменяют друг друга.
    ///
    /// При ничьей по времени — та версия, где полей заполнено больше.
    /// Часы двух телефонов расходятся на секунды, и разумнее взять ту,
    /// где данных больше, чем ту, где их стёрли.
    static func resolve(local: DogPayload, remote: DogPayload) -> DogPayload {
        precondition(local.id == remote.id)
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

        // Чем доза привязана к препарату — не теряется ни одной
        // стороной: по имени чужая отметка находит схему, когда id
        // не подошёл, а пустая привязка оставила бы дозу висеть
        // ни на чём.
        winner.medicationID = winner.medicationID ?? local.medicationID ?? remote.medicationID
        winner.medicationName = winner.medicationName ?? local.medicationName ?? remote.medicationName

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

    /// То же для профиля: считается только заполняемое руками.
    /// Кличка и вес есть всегда — по ним стороны не различишь.
    private static func filledFields(_ payload: DogPayload) -> Int {
        var count = 0
        if payload.breed?.isEmpty == false { count += 1 }
        if payload.birthDate != nil { count += 1 }
        if payload.targetWeightLow != nil { count += 1 }
        if payload.targetWeightHigh != nil { count += 1 }
        if !payload.foodBrand.isEmpty { count += 1 }
        if payload.dailyNormGrams != nil { count += 1 }
        if !payload.forbiddenFoods.isEmpty { count += 1 }
        if payload.chipNumber?.isEmpty == false { count += 1 }
        if payload.vetName?.isEmpty == false { count += 1 }
        if payload.vetPhone?.isEmpty == false { count += 1 }
        if payload.clinicName?.isEmpty == false { count += 1 }
        if payload.clinicPhone?.isEmpty == false { count += 1 }
        if payload.distinctiveMarks?.isEmpty == false { count += 1 }
        return count
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
