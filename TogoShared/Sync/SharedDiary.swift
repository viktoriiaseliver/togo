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
    /// С 07.10.2026 ездят **шесть**: собака, лента, уход, схемы лечения,
    /// приёмы и справочник клиник. Решение Виктории от 23.09 — все типы,
    /// а не минимальный набор.
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
    ///
    /// **Перечисление объявляет больше типов, чем ездит, и это надо
    /// читать осторожно.** Замер 07.10.2026 (`grep CKRecord(` по всему
    /// дереву): записи создаются ровно для шести типов. `weight`
    /// и `member` объявлены и не создаются ни разу — то есть история
    /// веса и состав семьи ко второму человеку не едут вовсе.
    ///
    /// > **Перечисление из семи читалось как семь едущих типов.**
    /// > Список имён — это заявка, а не замер.
    ///
    /// Долг назван по моделям в `DogPayloadParityTests.неЕздитПока`,
    /// с датой у каждой: двенадцать моделей из семнадцати не доезжают
    /// до второго человека, и ровно поэтому список держится там,
    /// а не здесь — чтобы он краснел, когда к нему добавят
    /// восемнадцатую модель молча.
    enum RecordType: String, CaseIterable, Sendable {
        case dog = "Dog"
        case event = "LogEvent"
        case care = "CareTask"
        case medication = "Medication"
        case dose = "DoseRecord"
        /// Взвешивания — ездят с 07.10.2026.
        ///
        /// **Тип был объявлен с самого начала и не создавался ни разу.**
        /// Поймал это сторож `RecordTypeUsedTests`, заведённый в тот же
        /// вечер под класс «объявлено, а писателя нет» — четыре случая
        /// за день.
        ///
        /// Ущерб был не в графике: **вес — то, от чего считается доза**,
        /// и расхождение веса между двумя людьми даёт расхождение дозы.
        case weight = "WeightEntry"
        case member = "FamilyMember"
        /// Справочник клиник — с 07.10.2026, шаг 0 медицинского слоя.
        case clinic = "Clinic"
        /// Медкнижка — с 07.10.2026.
        ///
        /// **Зачем она ездит, одной строкой:** в клинику собаку ведёт
        /// тот, кто сегодня свободен, а бланки лежат на телефоне
        /// хозяйки. Без обмена второй человек приходит к врачу
        /// с пересказом.
        case labResult = "LabResult"
        case vetVisit = "VetVisit"
        case diagnosis = "Diagnosis"
        case prescription = "Prescription"
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

    /// Девять полей ленты, не ехавших до 07.10.2026.
    ///
    /// Все девять числились «про семью» с тех пор, как появились,
    /// и в нагрузку не входили. Нашёл их обобщённый сторож паритета
    /// в тот час, когда перестал смотреть одну модель из семнадцати.
    ///
    /// **`askSignal` — самое дорогое из девяти.** Это «как попросил»:
    /// заглавная строка продукта, та самая, что стоит в описании
    /// App Store. Второй человек видел запись «просится» и **не видел,
    /// чем именно** — скулил, тёрся, стоял у двери. То есть ровно то,
    /// ради чего дневник ведут вдвоём.
    ///
    /// **`isDayOnly` — оговорка «часа не помню», без которой число
    /// лжёт.** `WalkRhythm` отбрасывает такие записи, считая обычное
    /// время выхода; приехав без флага, запись попадёт в счёт как
    /// точная, и «обычно выходите в 7:15» соберётся из догадок.
    ///
    /// **`enteredAt` — когда отметку ВВЕЛИ, против `date` — когда
    /// событие случилось.** Разница в них и есть ответ на вопрос
    /// «вспомнил или записал сразу».
    ///
    /// **`editedBy` возится, хотя писателя у него в приложении нет
    /// ни одного** (замер 07.10). Поле хранимое и уже едет в архив;
    /// не повезти его значило бы завести второй путь для тех же
    /// данных — а два пути расходятся молча. Появится экран правки —
    /// обмен не окажется неполным задним числом.
    ///
    /// `toldFamily`, `origin`, `reactionTrigger`, `reactionDistance`
    /// и `trainingSessionID` — факты о событии: сказали ли семье,
    /// откуда запись, на что и с какого расстояния была реакция,
    /// к какому занятию относится.
    var askSignal: String? = nil
    var isDayOnly: Bool? = nil
    var enteredAt: Date? = nil
    var editedBy: String? = nil
    var origin: String? = nil
    var reactionTrigger: String? = nil
    var reactionDistance: String? = nil
    var toldFamily: Bool? = nil
    var trainingSessionID: UUID? = nil

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
/// **Чего здесь нет и почему. Закрытость списка теперь ОХРАНЯЕТСЯ —
/// и предсказание сработало.** Прежняя редакция этого абзаца
/// говорила: «сторожа `DogPayloadParityTests` ещё нет; появится он —
/// эта фраза станет ложной, и `grep DogPayloadParityTests` её найдёт».
/// Сторож появился 05.10, обобщён на все модели 07.10 — и `grep`
/// привёл сюда ровно так, как было задумано.
///
/// > **Запись, которая называет СПОСОБ себя опровергнуть, стареет
/// > громко.** Этот абзац — единственный за вечер, который не пришлось
/// > ловить замером: он сам сказал, чем его проверить.
///
/// Дыра не была теоретической: те двенадцать полей, что поехали
/// 05.10.2026, нашли **руками**, перечитав модель поле за полем.
/// А 07.10 обобщённый сторож нашёл ещё семнадцать — девять у ленты
/// и восемь у схемы лечения, — и каждое числилось «про семью» с тех
/// пор, как появилось.
///
/// `DeviceLocalFieldTests` на этот вопрос не отвечает по устройству —
/// он делит поля на «про семью» и «про телефон» и про нагрузку обмена
/// не знает.
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

    /// Прививка: номер партии, срок годности и где её сделали.
    ///
    /// **Три поля шага 0, 07.10.2026.** Заведены в модели тем же днём
    /// и в нагрузку не попали: числились «про семью» и не ехали никуда.
    ///
    /// **Клиника — и по id, и по имени, и это не избыточность.**
    /// Тот же урок, что у `DosePayload.medicationName`: запись клиники
    /// может приехать позже дела ухода, обмен могли включить посреди
    /// курса, а справочник второй человек мог завести своей рукой
    /// и со своим UUID. Промах по id здесь норма, а не сбой; без имени
    /// прививка легла бы без места, где её сделали.
    var clinicID: UUID? = nil
    var clinicName: String? = nil
    var vaccineBatch: String? = nil
    var vaccineValidUntil: Date? = nil

    var changedAt: Date
}

/// Клиника или лаборатория из справочника.
///
/// **Зачем ездит.** В карте Стича одиннадцать организаций, и каждая
/// встречается в среднем в четырёх записях. Без обмена у второго
/// человека справочник пуст: он видит прививку и не видит, где её
/// сделали, а на вопрос «куда вести в следующий раз» ответа нет.
/// Это тот же сценарий, что уже оплачен листом для догситтера —
/// человек один с собакой, и нужное ему лежит у хозяйки.
///
/// **Телефон ездит вместе с именем нарочно.** Везти одно имя было бы
/// дешевле и бессмысленно: название клиники без номера не помогает
/// в тот час, когда с собакой что-то не так.
/// Взвешивание.
///
/// **Зачем ездит.** Вес из профиля (`Dog.weightKg`) возился с самого
/// начала, а история взвешиваний — нет: тип записи был объявлен
/// и не создавался ни разу. Снаружи это выглядело как «вес виден»,
/// и вопрос «а график?» никто не задал.
///
/// Ущерб не в графике: **доза считается от веса**, и расхождение веса
/// между двумя людьми даёт расхождение дозы. Формулировку дал
/// `projects-00` 07.10.2026.
///
/// **`date` и `changedAt` — разные величины.** Первое — день, когда
/// взвесили; второе — когда правили запись. Спор решает второе: иначе
/// исправление опечатки в старом взвешивании всегда проигрывало бы
/// новой записи, то есть опечатка оставалась бы навсегда.
nonisolated struct WeightPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var date: Date
    var kg: Double
    var changedAt: Date
}

/// Строка анализа.
///
/// **Три поля значения вместо одного, и это не избыточность.** `value` —
/// число; `belowLimit` — `<0,1 нг/дл` с бланка; `textValue` — описание
/// там, где числа нет вовсе. Сложи их в одно, и предел прибора станет
/// числом 0,1, то есть **тихо неверным значением вместо видимо
/// неизвестного**.
///
/// `method` возится потому, что свободный Т4 равновесным диализом
/// не сравним с обычным: без метода два значения станут противоречием
/// там, где его нет.
///
/// `labMark` — отметка самой лаборатории, факт из документа, а не наш
/// вердикт. Везётся отдельно от референса нарочно: расхождение нашего
/// счёта с бланком — находка, а не ошибка.
nonisolated struct LabResultPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var sampledOn: Date
    var sampledAt: Date?
    var laboratory: String
    var reportNumber: String
    var section: String
    var indicator: String
    var value: Double?
    var belowLimit: Double?
    var aboveLimit: Double?
    var textValue: String?
    var unit: String
    var referenceLow: Double?
    var referenceHigh: Double?
    var method: String?
    var labMark: String
    var note: String
    var changedAt: Date
}

/// Визит к врачу. Онлайн-консультация — такой же визит.
///
/// Клиника — и по id, и по имени, по той же причине, что у дела ухода:
/// справочник второй человек мог завести своей рукой до включения
/// обмена, и промах по id там норма, а не сбой.
nonisolated struct VetVisitPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var date: Date
    var clinicID: UUID?
    var clinicName: String?
    var doctor: String
    var reason: String
    var conclusion: String
    var changedAt: Date
}

/// Диагноз.
///
/// **`status` возится обязательно:** по подтверждённому лечат,
/// по гипотезе ищут. Второй человек, увидевший гипотезу как
/// подтверждённый диагноз, начнёт лечить по ней.
nonisolated struct DiagnosisPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var wording: String
    var status: String
    var madeOn: Date
    var madeBy: String
    var evidence: String
    var changedAt: Date
}

/// Назначение.
///
/// **`dogWeightKg` — часть назначения, а не справка:** доза считается
/// от веса на дату. Это поле важно вдвойне, потому что сама история
/// взвешиваний ко второму человеку пока не едет — значит проверить
/// дозу задним числом он сможет только отсюда.
///
/// **`controlFrom`/`controlTo` — окно, а не дата.** Три врача назвали
/// три интервала; свести к одной дате значило бы придумать число
/// за врача.
nonisolated struct PrescriptionPayload: Equatable, Sendable, Codable {
    var id: UUID
    var dogID: UUID?
    var number: String
    var date: Date
    var clinicID: UUID?
    var clinicName: String?
    var doctor: String
    var dogWeightKg: Double?
    var medicationName: String
    var dosage: String
    var schedule: String
    var duration: String
    var pharmacyForm: String?
    var controlFromWeeks: Int
    var controlToWeeks: Int
    var dispensed: String
    var instruction: String
    var source: String
    var changedAt: Date
}

nonisolated struct ClinicPayload: Equatable, Sendable, Codable {
    var id: UUID
    var name: String
    var detail: String?
    var isLab: Bool
    var phone: String?
    var createdAt: Date
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

    /// Номер назначения — шаг 0, 07.10.2026. Его называют в аптеке,
    /// чтобы продлить, и в клинике, чтобы найти запись; делает это
    /// тот, кто сегодня свободен, а не владелец телефона.
    var prescriptionNumber: String? = nil

    /// Единица дозы — и это самое опасное поле, которое не ехало.
    ///
    /// **Найдено 07.10.2026 обобщённым сторожем, не глазом.** Поле
    /// числилось «про семью» с тех пор, как появилось, и в нагрузке
    /// его не было: у второго человека схема приезжала **без единицы**.
    ///
    /// > «0,5» не значит ничего: половина таблетки, половина
    /// > миллилитра и половина капли — три разные дозы.
    ///
    /// Это не путаница в дневнике, а передозировка — и ровно теми
    /// словами риск записан в архивном снимке с 07.10, где поле везли
    /// правильно. То есть архив знал, а обмен нет: **два пути для одних
    /// данных, и расходятся они молча.**
    var unitRaw: String? = nil

    /// Расписание дозы по слотам: в котором часу сколько. Без него
    /// у второго человека схема «дважды в день» не знает, сколько
    /// именно в каждый приём.
    var doseSlotsData: [DoseSlot]? = nil

    /// Сроки: конец курса, годен до, вскрыт, сколько дней после вскрытия
    /// и напоминать ли о годности.
    ///
    /// **Срок годности и срок после вскрытия — ДВА поля**, и это главное
    /// в них: одним полем разница «годен до» против «вскрыт, дальше
    /// N дней» потерялась бы у человека с открытым флаконом капель,
    /// то есть там, где ошибка измеряется дозой.
    var courseEnd: Date? = nil
    var expiry: Date? = nil
    var openedAt: Date? = nil
    var shelfAfterOpenDays: Int? = nil
    var remindBeforeExpiry: Bool? = nil

    /// Можно ли дать на улице — **ответ человека, а не наш вывод
    /// из соседних полей.** Второй человек, собравшийся на прогулку
    /// с каплями в глаз, обязан видеть тот же ответ, что дала хозяйка.
    var canGiveOutside: Bool? = nil

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

    /// Спор о взвешивании.
    ///
    /// Побеждает правка, что позже. При ничьей — **меньший вес**,
    /// и это не «больше полей», а решение о цене ошибки: доза
    /// считается от веса, и завысив вес, мы завысим дозу. Ошибиться
    /// в сторону меньшей дозы безопаснее, чем в сторону большей.
    ///
    /// Ничья здесь редка (одно взвешивание правят двое в одну
    /// секунду), но правило всё равно должно быть названо: иначе
    /// исход решит порядок, в котором пришли записи, а он не наш.
    static func resolve(local: WeightPayload, remote: WeightPayload) -> WeightPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        return local.kg <= remote.kg ? local : remote
    }

    // MARK: Медкнижка
    //
    // У всех четырёх правило одно: побеждает правка, что позже.
    // Своих «сильных» полей, как «дано» у дозы или удаление у ленты,
    // здесь нет — медкнижка это **перепечатка документа**, а не
    // действие. Расхождение двух телефонов о бланке значит, что один
    // из них набрал его точнее, а не что кто-то что-то сделал.
    //
    // При ничьей по времени — та версия, где полей заполнено больше:
    // часы расходятся на секунды, и терять набранное из-за этого
    // нельзя. Ровно то же правило, что у профиля собаки.

    static func resolve(local: LabResultPayload, remote: LabResultPayload) -> LabResultPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        func заполнено(_ p: LabResultPayload) -> Int {
            var счёт = 0
            // Значение считается ОДИН раз, какой бы из трёх форм оно
            // ни было: иначе версия с числом проиграла бы версии,
            // где заполнены и число, и предел, — а так не бывает.
            if p.value != nil || p.belowLimit != nil
                || p.aboveLimit != nil || p.textValue?.isEmpty == false { счёт += 1 }
            if p.sampledAt != nil { счёт += 1 }
            if p.referenceLow != nil || p.referenceHigh != nil { счёт += 1 }
            if p.method?.isEmpty == false { счёт += 1 }
            if !p.labMark.isEmpty { счёт += 1 }
            if !p.note.isEmpty { счёт += 1 }
            if !p.unit.isEmpty { счёт += 1 }
            if !p.reportNumber.isEmpty { счёт += 1 }
            return счёт
        }
        return заполнено(local) >= заполнено(remote) ? local : remote
    }

    static func resolve(local: VetVisitPayload, remote: VetVisitPayload) -> VetVisitPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        func заполнено(_ p: VetVisitPayload) -> Int {
            var счёт = 0
            if !p.conclusion.isEmpty { счёт += 1 }
            if !p.doctor.isEmpty { счёт += 1 }
            if p.clinicID != nil || p.clinicName?.isEmpty == false { счёт += 1 }
            return счёт
        }
        return заполнено(local) >= заполнено(remote) ? local : remote
    }

    static func resolve(local: DiagnosisPayload, remote: DiagnosisPayload) -> DiagnosisPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        // При ничьей выигрывает **снятый** диагноз, и это не «больше
        // полей», а решение: по снятому не лечат. Та же форма, что
        // у дозы, где «дано» побеждает всегда, — цена ошибки
        // несимметрична. Лечить по снятому диагнозу хуже, чем
        // не лечить по подтверждённому лишний час до следующего круга.
        if local.status != remote.status {
            if local.status == DiagnosisStatus.withdrawn.rawValue { return local }
            if remote.status == DiagnosisStatus.withdrawn.rawValue { return remote }
        }
        func заполнено(_ p: DiagnosisPayload) -> Int {
            var счёт = 0
            if !p.wording.isEmpty { счёт += 1 }
            if !p.madeBy.isEmpty { счёт += 1 }
            if !p.evidence.isEmpty { счёт += 1 }
            return счёт
        }
        return заполнено(local) >= заполнено(remote) ? local : remote
    }

    static func resolve(local: PrescriptionPayload, remote: PrescriptionPayload) -> PrescriptionPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        func заполнено(_ p: PrescriptionPayload) -> Int {
            var счёт = 0
            if !p.dosage.isEmpty { счёт += 1 }
            if !p.schedule.isEmpty { счёт += 1 }
            if !p.duration.isEmpty { счёт += 1 }
            if p.dogWeightKg != nil { счёт += 1 }
            if p.pharmacyForm?.isEmpty == false { счёт += 1 }
            // Окно контроля — единственное место, откуда приложение
            // знает, когда напоминать. Версия с окном не должна
            // проигрывать версии без него из-за расхождения часов.
            if p.controlFromWeeks > 0 || p.controlToWeeks > 0 { счёт += 1 }
            if !p.instruction.isEmpty { счёт += 1 }
            if !p.source.isEmpty { счёт += 1 }
            if !p.dispensed.isEmpty { счёт += 1 }
            return счёт
        }
        return заполнено(local) >= заполнено(remote) ? local : remote
    }

    /// Спор о записи справочника.
    ///
    /// Побеждает правка, что позже, — как у профиля. При ничьей
    /// по времени берётся та, где **полей заполнено больше**: клиника
    /// это набор контактов, и разумнее взять версию с телефоном, чем
    /// ту, где его стёрли. Два телефона расходятся на секунды, и ничья
    /// здесь не редкость — справочник правят оба, набирая одно и то же.
    static func resolve(local: ClinicPayload, remote: ClinicPayload) -> ClinicPayload {
        precondition(local.id == remote.id)
        if local.changedAt != remote.changedAt {
            return local.changedAt > remote.changedAt ? local : remote
        }
        func заполнено(_ p: ClinicPayload) -> Int {
            var счёт = 0
            if Fmt.notBlank(p.name) != nil { счёт += 1 }
            if p.detail?.isEmpty == false { счёт += 1 }
            if p.phone?.isEmpty == false { счёт += 1 }
            return счёт
        }
        return заполнено(local) >= заполнено(remote) ? local : remote
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
        // Поля, поехавшие 07.10.2026, считаются здесь по той же
        // причине, по которой в профиле считается лист ситтера:
        // не считать их значило бы, что версия С «как попросил»
        // проигрывает версии без него при ничьей по времени, —
        // то есть при расхождении часов на секунды победит та,
        // где данных меньше.
        if payload.askSignal != nil { count += 1 }
        if payload.isDayOnly != nil { count += 1 }
        if payload.enteredAt != nil { count += 1 }
        if payload.editedBy?.isEmpty == false { count += 1 }
        if payload.origin != nil { count += 1 }
        if payload.reactionTrigger != nil { count += 1 }
        if payload.reactionDistance != nil { count += 1 }
        if payload.trainingSessionID != nil { count += 1 }
        return count
    }
}
