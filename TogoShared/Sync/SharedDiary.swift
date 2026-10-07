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
    /// **До 23.09.2026 ездили два вида из семи** — `event` и `dose`, —
    /// и это стоило отзыва: «мама не видит то же, что и я, и не видит
    /// мою собаку». Приглашение работало и приводило в пустую комнату.
    ///
    /// Теперь ездят пять: собака, лента, уход, схемы лечения и приёмы.
    /// Решение Виктории от 23.09 — все типы, а не минимальный набор.
    ///
    /// Не ездят двое, и каждый по своей причине:
    /// - `weight` — взвешивания лежат в отдельной сущности и ждут
    ///   очереди; вес из профиля при этом ездит;
    /// - `member` — список семьи у каждого свой, и «я» на втором
    ///   телефоне уже один раз оказалась карточкой владельца
    ///   (`5c70324`). Возить его — значит повторить это.
    ///
    /// Фотографии не ездят вовсе: они сделали бы обмен тяжёлым ровно
    /// там, где он должен быть мгновенным.
    ///
    /// **На экране написано то же самое.** Обещать больше, чем умеет
    /// обмен, дневнику с дозами нельзя — и меньше тоже: тогда человек
    /// не воспользуется тем, что есть.
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
/// **Чего здесь нет и почему.** Список закрытый, и закрытость его
/// **не проверяет пока ничто**: сторожа `DogPayloadParityTests` —
/// «поле `Dog` числится „про семью“, но не едет здесь, и причина
/// не названа» — ещё нет. Появится он — эта фраза станет ложной,
/// и `grep DogPayloadParityTests` её найдёт.
///
/// Дыра не теоретическая: те двенадцать полей, что поехали 05.10.2026,
/// нашли **руками**, перечитав модель поле за полем. Тринадцатое найдут
/// так же. `DeviceLocalFieldTests` на этот вопрос не отвечает — он
/// делит поля на «про семью» и «про телефон» и про нагрузку обмена
/// не знает: `Dog.photo` и `Dog.createdAt` лежат у него в списке
/// «которым уезжать положено» и не едут ни одно.
///
/// - `photo` — решение брифа 22.09: снимки сделали бы обмен тяжёлым
///   ровно там, где он должен быть мгновенным. Фото каждый ставит у себя.
/// - `createdAt` — факт о ЗАПИСИ, а не о собаке; подробный довод стоит
///   у самого поля в `Dog.swift`. Когда собака появилась здесь, помнит
///   `DogOrigin`.
///
/// **Третьим здесь до 07.10.2026 стояли заметки для ситтера** — «их
/// пишет тот, кто уезжает, под конкретную поездку; общими они не
/// бывают», — и строками ниже эти же пять полей теперь едут. Довод был
/// неверен в обе стороны: лист пишет как раз остающийся, и существует
/// он ровно для того часа, когда хозяина рядом нет.
///
/// Запись оставлена, потому что интересен не довод, а место. Проза над
/// таблицей и таблица — две поверхности **одного файла**, и 05.10 правка
/// дошла до второй, не задев первую. Искали поле, а не утверждение
/// о полях.
///
/// > **Исключение с объяснением читается как решение и потому
/// > не перечитывается.** Полтора дня заголовок отрицал то, что код
/// > под ним делал.
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
    ///
    /// **Три номера документов стояли в одной группе одного экрана,
    /// а ездил один.** `chipNumber` возился с самого начала,
    /// `passportNumber` и `insuranceNumber` — нет. Асимметрия выглядела
    /// недосмотром, потому что им и была (замер togo-f5, 05.10.2026):
    /// у страховки номер нужен ровно в тот час, когда с собакой что-то
    /// случилось, а рядом не хозяин.
    var chipNumber: String?
    var passportNumber: String?
    var insuranceNumber: String?
    var vetName: String?
    var vetPhone: String?
    var clinicName: String?
    var clinicPhone: String?
    var distinctiveMarks: String?

    /// Лист для догситтера: чем кормить, когда гулять, что нельзя,
    /// кому звонить.
    ///
    /// **До 05.10.2026 он на втором телефоне был ПУСТ.** Пять полей
    /// хозяйка заполняет один раз, ситтер только читает — и не читал
    /// ничего: в нагрузку обмена они не входили. Это не «работает
    /// частично»: лист существует ровно для того часа, когда хозяина
    /// нет рядом, то есть функция не работала **в единственном
    /// сценарии, ради которого написана**.
    ///
    /// Рядом с находкой про общий доступ («у гостя всё получалось
    /// и ничего не происходило») выходит, что ситтер не был обслужен
    /// дважды — ни доступом, ни данными. Поэтому эти пять поехали
    /// первыми из двенадцати, а не по порядку в модели.
    var sitterFood: String
    var sitterDose: String
    var sitterWalks: String
    var sitterForbidden: String
    var sitterEscalation: String

    /// Как занимаются с собакой: чем награждают, чем маркируют,
    /// сколько длится занятие и идут ли лакомства из дневной порции.
    ///
    /// Последнее — не про дрессировку, а про еду: гость без него
    /// считает дневную норму иначе, чем хозяйка, и спорят они
    /// не о тренировке, а о том, сколько собака съела.
    var rewards: [String]
    var markerKind: String
    var sessionLengthMinutes: Int
    var trainingFoodFromPortion: Bool

    var changedAt: Date
}

/// Дело ухода: мытьё, когти, капли от клещей.
///
/// **Зачем ездит.** Без расписания «план дня» у гостя пуст: он видит
/// ленту чужих отметок и ни одного дела, которое надо сделать. Мама,
/// оставшаяся с собакой на выходные, узнавала о каплях от клещей
/// из сообщения, а не из приложения.
///
/// `streak` и `snoozeCount` ездят намеренно: «делали пять дней подряд»
/// — общий факт про собаку, а не заслуга телефона. Разъехавшись, они
/// показали бы двоим разные числа про одно и то же.
nonisolated struct CarePayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var title: String
    var detail: String
    var kind: String
    var category: String
    var intervalDays: Int
    var scheduledDate: Date?
    var remindDaysBefore: Int
    var lastDone: Date?
    var streak: Int
    var seasonStartMonth: Int?
    var seasonEndMonth: Int?
    var snoozeCount: Int
    var changedAt: Date
}

/// Схема лечения.
///
/// **Зачем ездит.** Дозы ездили с самого начала, а препарат, к которому
/// они относятся, — нет. У гостя приёмы приходили без названия, и
/// `SharedDiaryInbox.medication(for:)` искал схему по имени, потому что
/// «промах по id — норма, а не сбой». С 23.09.2026 схемы ездят, и промах
/// по id станет тем, чем он и должен быть: редкостью.
///
/// **Запас таблеток не ездит.** `stockLeft` и `stockTotal` — это про
/// коробку, которая лежит у кого-то дома. У мамы своя упаковка, и
/// сложить два запаса в одно число значило бы сказать обоим неправду.
nonisolated struct MedicationPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var name: String
    var doseText: String
    var times: [Int]
    var fastingMinutes: Int
    var fastingBeforeMinutes: Int
    var minutesAfterMeal: Int
    var isPaused: Bool
    var prescriber: String?
    var cancelledAt: Date?
    var cancelledNote: String?
    var changedAt: Date
}

/// Отметка приёма препарата.
nonisolated struct DosePayload: Equatable, Sendable, Codable {
    var id: UUID
    var medicationID: UUID?

    /// Как препарат называется — на случай, когда id не подошёл.
    ///
    /// **Оставлено после того, как схемы поехали.** До 23.09.2026 они
    /// не обменивались вовсе, у второго человека тот же препарат был
    /// заведён своей рукой и с другим UUID, и промах по id был нормой.
    /// Теперь схемы ездят — но промах остаётся возможным: доза приезжает
    /// раньше схемы, схему завели до обмена, обмен включили посреди
    /// курса. Связь по имени стоит дёшево, а без неё чужое «дано»
    /// ложится на дозу без препарата и на экране не появляется.
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

    /// Спор о деле ухода и о схеме лечения.
    ///
    /// Правило то же, что у профиля: побеждает правка, что позже.
    ///
    /// **Отмена схемы — не то же, что удаление записи.** У ленты
    /// «удаление сильнее правки», потому что вернуть удалённое стоит
    /// один тап, а «я удалила, а оно вернулось» рушит доверие. У схемы
    /// отмена это `cancelledAt`, обычное поле: оно едет вместе
    /// с остальными и проигрывает более поздней правке — как и должно,
    /// если врач отменил курс, а потом назначил снова.
    static func resolve(local: CarePayload, remote: CarePayload) -> CarePayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        // При ничьей — тот, кто делал позже: `lastDone` это факт,
        // а не мнение, и потерять его хуже, чем потерять правку названия.
        return (local.lastDone ?? .distantPast) >= (remote.lastDone ?? .distantPast)
            ? local : remote
    }

    static func resolve(local: MedicationPayload, remote: MedicationPayload) -> MedicationPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        // При ничьей выигрывает пауза и отмена: не дать таблетку,
        // которую отменили, безопаснее, чем дать отменённую.
        // Это единственное место, где у схемы правило не «позже»,
        // и цена ошибки здесь та же, что у дозы.
        var winner = local
        winner.isPaused = local.isPaused || remote.isPaused
        winner.cancelledAt = local.cancelledAt ?? remote.cancelledAt
        winner.cancelledNote = winner.cancelledNote ?? remote.cancelledNote
        return winner
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
        if payload.passportNumber?.isEmpty == false { count += 1 }
        if payload.insuranceNumber?.isEmpty == false { count += 1 }
        if payload.vetName?.isEmpty == false { count += 1 }
        if payload.vetPhone?.isEmpty == false { count += 1 }
        if payload.clinicName?.isEmpty == false { count += 1 }
        if payload.clinicPhone?.isEmpty == false { count += 1 }
        if payload.distinctiveMarks?.isEmpty == false { count += 1 }
        // Лист ситтера — самое заполняемое руками место профиля: пять
        // полей, и все пишет человек. Не считать их значило бы, что
        // версия С листом проигрывает версии без него при разрешении
        // спора — то есть лист, который хозяйка только что написала,
        // стёрся бы пустым от второго телефона.
        if !payload.sitterFood.isEmpty { count += 1 }
        if !payload.sitterDose.isEmpty { count += 1 }
        if !payload.sitterWalks.isEmpty { count += 1 }
        if !payload.sitterForbidden.isEmpty { count += 1 }
        if !payload.sitterEscalation.isEmpty { count += 1 }
        if !payload.rewards.isEmpty { count += 1 }
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
