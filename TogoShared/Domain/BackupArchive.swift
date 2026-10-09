import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Полный слепок дневника: то, что переживает переустановку и переезд
/// на новый телефон.
///
/// Формат намеренно простой — плоский JSON с версией. Его можно открыть
/// текстовым редактором и увидеть, что именно уезжает: приложение,
/// которое хранит здоровье собаки, не имеет права быть чёрным ящиком.
nonisolated struct BackupArchive: Codable, Sendable {
    /// Версия формата. Читатель обязан проверить её первой строкой.
    var formatVersion: Int = 1
    var createdAt: Date
    var appVersion: String

    var dogs: [DogSnapshot]
    var members: [MemberSnapshot]
    var episodes: [EpisodeSnapshot]
    /// Навыки подготовки к процедурам.
    ///
    /// **Корневым массивом, а не полем внутри `DogSnapshot`, и это
    /// не стиль.** У `ProcedureSkill` нет связи с собакой вовсе — ни
    /// `dog`, ни обратной (`TogoShared/Models/Training.swift:92–99`:
    /// семь полей, ни одного `@Relationship`). Положить его внутрь
    /// собаки значило бы придумать принадлежность, которой в модели
    /// нет, и при двух собаках решать за человека, чей навык.
    ///
    /// **До 07.10.2026 этого снимка не было вовсе** — слово
    /// `ProcedureSkill` встречалось в `Backup.swift`
    /// и `BackupArchive.swift` ноль раз. Замер `togo-1e`, проверен
    /// этой сессией **со стороны сборщика**, а не по объявлению
    /// структуры: искать надо там, где поле заполняют, а не там,
    /// где объявляют.
    ///
    /// Опциональность — для старых файлов, как у `stocks`, `heats`,
    /// `documents` и `daysOut`.
    var procedureSkills: [ProcedureSkillSnapshot]?

    /// Справочник клиник и лабораторий.
    ///
    /// **Корневым массивом по той же причине, что `procedureSkills`:**
    /// у клиники нет связи с собакой. К одному врачу ходят обе собаки,
    /// и положить справочник внутрь собаки значило бы раздвоить
    /// одиннадцать организаций Стича на столько копий, сколько собак
    /// в дневнике.
    ///
    /// **Заведён 07.10.2026 вместе с самой моделью — и это
    /// не предусмотрительность, а починка.** Шагом 0 медицинского
    /// слоя `Clinic` появилась в схеме и не попала ни в архив,
    /// ни в общий дневник: все её поля числились «про семью»
    /// и не ехали никуда. ТЗ §4 требует обратного — поле входит
    /// в архив и в обмен тем же коммитом.
    var clinics: [ClinicSnapshot]?

    /// Клиника или лаборатория.
    ///
    /// `careTasks` здесь нет: связь хранится **со стороны дела ухода**
    /// (`CareTaskSnapshot.clinicName`), одним концом. Два конца
    /// в одном файле разошлись бы при первой правке руками, а файл
    /// этот человек открывает текстовым редактором — он так задуман.
    struct ClinicSnapshot: Codable, Sendable {
        var name: String
        var detail: String?
        var isLab: Bool
        var phone: String?
        var createdAt: Date
    }

    /// Навык подготовки к процедуре.
    ///
    /// `targetDate` здесь есть, хотя писателя у него в приложении
    /// нет ни одного (замер `togo-1e`): поле хранимое, и если
    /// однажды появится экран, который его ставит, архив не окажется
    /// неполным задним числом. Обратное решение — не возить то, чего
    /// не вводят, — завело бы исключение, про которое через месяц
    /// никто не вспомнит.
    struct ProcedureSkillSnapshot: Codable, Sendable {
        var title: String
        var detail: String
        var statusRaw: String
        var targetDate: Date?
        var successes: Int
        var attempts: Int
    }

    struct DogSnapshot: Codable, Sendable {
        var name: String
        var photo: Data?
        var breed: String?
        var birthDate: Date?
        var weightKg: Double
        var targetWeightLow: Double?
        var targetWeightHigh: Double?
        var foodBrand: String
        var portionGrams: Int
        var mealsPerDay: Int
        var mealTimes: [Int]
        var forbiddenFoods: [String]
        var dailyNormGrams: Int?
        var rewards: [String]
        var trainingFoodFromPortion: Bool
        var markerKindRaw: String
        var sessionLengthMinutes: Int
        var isOnTreatment: Bool
        var createdAt: Date

        // Семнадцать полей, добавленных 07.10.2026. Все опциональные:
        // архивы, снятые раньше, этих ключей не знают и обязаны
        // читаться.
        //
        // **Это и есть медицинская карточка собаки, и архив её терял
        // целиком.** Номер чипа, номер паспорта, номер страховки,
        // врач и клиника с телефонами, приметы для объявления
        // о пропаже — всё то, что спрашивают в клинике и в полиции,
        // и всё то, что человек вводит один раз и больше никогда
        // не вспомнит.
        //
        // Пять полей листа ситтера — туда же: их пишут один раз,
        // и переустановка телефона стирала их без следа.
        //
        // `sexRaw` и `isNeutered` не косметика: от них зависит
        // календарь течки, то есть видит ли человек цикл вообще.
        var sexRaw: String?
        var isNeutered: Bool?
        var wakeMinuteOfDay: Int?
        var sleepMinuteOfDay: Int?
        var chipNumber: String?
        var passportNumber: String?
        var insuranceNumber: String?
        var vetName: String?
        var vetPhone: String?
        var clinicName: String?
        var clinicPhone: String?
        var distinctiveMarks: String?
        var sitterFood: String?
        var sitterDose: String?
        var sitterWalks: String?
        var sitterForbidden: String?
        var sitterEscalation: String?

        var events: [EventSnapshot]
        var weights: [WeightSnapshot]
        var careTasks: [CareTaskSnapshot]
        var medications: [MedicationSnapshot]
        var trainingSteps: [TrainingStepSnapshot]
        var trainingSessions: [TrainingSessionSnapshot]
        var trips: [TripSnapshot]
        /// Появилось позже — у старых файлов этого поля нет.
        var stocks: [StockSnapshot]?
        var heats: [HeatSnapshot]?
        /// Снимки документов. Тоже позже: экрана у них не было вовсе,
        /// а значит, и сохранять было нечего.
        var documents: [DocumentSnapshot]?
        /// Выезды. Опциональность — не стиль: у файлов, сохранённых
        /// до 07.10.2026, этого поля нет, и прочитаться они обязаны.
        /// Та же причина, что у `stocks`, `heats` и `documents`.
        var daysOut: [DayOutSnapshot]?

        /// Медицинский слой — 07.10.2026. Внутри собаки, а не корневым
        /// списком: у всех четырёх есть `dog`, в отличие от клиник
        /// и навыков процедур.
        ///
        /// **Это медкнижка, и терять её при переезде нельзя ни строкой.**
        /// У Стича 127 анализов, 34 рецепта, восемь замеров щитовидной
        /// с часами после приёма — то, что собирали год по бланкам
        /// из четырёх лабораторий. Восстановить это неоткуда: бумажные
        /// бланки остались в клиниках, а письма врачей — в почте.
        var labResults: [LabResultSnapshot]?
        var vetVisits: [VetVisitSnapshot]?
        var diagnoses: [DiagnosisSnapshot]?
        var prescriptions: [PrescriptionSnapshot]?
    }

    /// Строка анализа.
    ///
    /// **Три поля значения вместо одного, и это не избыточность.**
    /// `value` — число; `belowLimit` — `<0,1 нг/дл` с бланка;
    /// `textValue` — «выделен штамм коагулазо-отрицательного
    /// стафилококка». Сложи их в одно, и предел прибора станет числом
    /// 0,1 — то есть **тихо неверным значением вместо видимо
    /// неизвестного**, а девять строк бактериологии не влезут вовсе.
    ///
    /// `method` возится потому, что свободный Т4 равновесным диализом
    /// не сравним с обычным: потеряв метод, два значения станут
    /// противоречием там, где его нет.
    ///
    /// `labMark` — отметка самой лаборатории, факт из документа,
    /// а не наш вердикт. Везётся отдельно от нормы нарочно:
    /// референс Т4 в карте менялся трижды, и расхождение нашего счёта
    /// с отметкой бланка — находка, а не ошибка.
    struct LabResultSnapshot: Codable, Sendable {
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
    }

    /// Визит к врачу. Онлайн-консультация — такой же визит.
    ///
    /// Клиника — **именем**, как у дела ухода: справочник лежит
    /// корневым списком `clinics`, и связь хранится одним концом.
    struct VetVisitSnapshot: Codable, Sendable {
        var date: Date
        var clinicName: String?
        var doctor: String
        var reasonRaw: String
        var conclusion: String
    }

    /// Диагноз. Статус везётся обязательно: по подтверждённому лечат,
    /// по гипотезе ищут, и потеряв различие, восстановленная карта
    /// скажет про гипотезу «подтверждён».
    struct DiagnosisSnapshot: Codable, Sendable {
        var wording: String
        var statusRaw: String
        var madeOn: Date
        var madeBy: String
        var evidence: String
    }

    /// Назначение.
    ///
    /// **`dogWeightKg` — часть назначения, а не справка:** доза
    /// считается от веса на дату, и без него проверить дозу задним
    /// числом нечем.
    ///
    /// **`pharmacyForm` живёт здесь, а не у схемы лечения**, потому
    /// что вопрос ретроспективный: «какая форма была в тот месяц,
    /// когда Т4 провалился». Рецепт датирован по природе, схема
    /// отвечает «какая сейчас» и переписывает историю молча.
    ///
    /// **`controlFromWeeks`/`controlToWeeks` — окно, а не дата.**
    /// Три врача назвали три интервала; свести к одной дате значило бы
    /// придумать число за врача.
    struct PrescriptionSnapshot: Codable, Sendable {
        var number: String
        var date: Date
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
    }

    /// Фотография документа целиком: паспорт, потерянный вместе
    /// с телефоном, восстанавливать неоткуда.
    struct DocumentSnapshot: Codable, Sendable {
        var title: String
        var image: Data?
        var addedAt: Date
        var note: String?
        /// Четыре поля шага 0 медицинского слоя, 07.10.2026.
        ///
        /// **`validUntil` — то, из-за чего шаг 0 и начался:** у Стича
        /// срок бешенства истёк 03.10, и назвать это приложение
        /// не могло — поля не было. Потерять его при переезде значило
        /// бы вернуть ровно то состояние, которое чинили.
        ///
        /// Этого разрыва не поймал ни один сторож: паритет архива
        /// сверяет `Dog`, `CareTask`, `Medication` и `DoseRecord` —
        /// четыре модели из семнадцати, и `DogDocument` не входит.
        /// Он был прав и слеп, и слепоту печатал о себе сам.
        var kindRaw: String?
        var number: String?
        var issuedBy: String?
        var validUntil: Date?
    }

    struct StockSnapshot: Codable, Sendable {
        var kindRaw: String
        var brand: String
        var packGrams: Int
        var packsLeft: Double
        var gramsPerDay: Int
        var openedAt: Date?
        // Добавлено 07.10.2026 по замеру `togo-1e`, проверено этой
        // сессией. Писателя у обоих полей сегодня нет ни одного —
        // и это не довод против, а механизм, которым они и выпали:
        //
        // > **Поле без экрана не видно ни в одном кадре, и потому
        // > не попадает в правку архива.**
        //
        // Оба перечислены поимённо в `SchemaVersions.swift:1446` среди
        // тринадцати полей V5, заведённых заранее под экраны хендоффа.
        // Десять из тринадцати архив уже несёт — ровно те, у которых
        // поверхность есть. Риск называется ДНЁМ, а не вероятностью:
        // в день приезда экранов у этих полей появится писатель,
        // а архив начнёт терять их молча, и связать два события будет
        // нечем — правка «завести экран» трогает модель и вид, а не
        // перенос.
        var expiry: Date?
        var shelfAfterOpenDays: Int?

        /// Когда человек последний раз пересчитал запас.
        ///
        /// **Не метка времени, а НЕСУЩЕЕ поле.** `FoodStock.usedGrams(at:)`
        /// на нём стоит: `guard let countedAt` и отсчёт дней от него.
        /// Потеряв его, `usedGrams` отдаёт ноль, `remainingGrams` —
        /// полный мешок, и человек на новом телефоне читает «хватит
        /// на тридцать дней» там, где корм кончается завтра.
        ///
        /// То есть потеря этого поля — не потеря даты, а **неверное
        /// число на экране**, и неверное в сторону спокойствия.
        /// Добавлено 07.10.2026, `togo-1e`.
        var countedAt: Date?
    }

    struct HeatSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var note: String?
    }

    /// День с человеком: по делам, в дороге, в гостях.
    ///
    /// **Появился в архиве 07.10.2026, и до этого его не было вовсе.**
    /// `DayOut` живёт в приложении давно: `TodayScreen` читает выезды
    /// запросом и меняет по ним поведение главного экрана,
    /// а «Удалить все данные» про них знает. Не знал только перенос.
    ///
    /// Цена молчания: человек, переезжающий на новый телефон, терял все
    /// выезды — и узнать об этом ему было негде. Это не дефект показа,
    /// на который жалуются; это потеря данных, которую обнаруживают
    /// через месяц, если вообще.
    struct DayOutSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var plannedHours: Int
        var note: String?
    }

    struct EventSnapshot: Codable, Sendable {
        var id: UUID
        var date: Date
        var kindRaw: String
        var authorName: String
        var isSynced: Bool
        var note: String?
        var outcomeRaw: String?
        var askSignalRaw: String?
        var durationSeconds: Int?
        var stoolFormRaw: String?
        var stoolFlagsRaw: [String]
        var grams: Int?
        var milliliters: Int?
        var fromPortion: Bool
        var incidentKindRaw: String?
        var incidentDetailRaw: String?
        var toldFamily: Bool
        var deletedAt: Date?
        var deletedBy: String?
        // Добавлено 07.10.2026, опциональные.
        //
        // **`isDayOnly` и `enteredAt` — одна мысль: «часа не помню».**
        // `WalkRhythm:71` такие записи ОТБРАСЫВАЕТ
        // (`recent.filter { !$0.isDayOnly }`), прежде чем считать
        // обычное время выхода, и делает это нарочно: промежуток между
        // двумя полуночами не промежуток, а «обычно выходите в 00:00» —
        // прямая ложь, собранная из отсутствующих данных.
        //
        // Архив терял флаг — и после восстановления дозаписанные
        // «вчера, часа не помню» становились неотличимы от точных.
        // То есть приложение начинало советовать человеку время выхода,
        // посчитанное по часам, которых никто не знал. Это не потеря
        // поля, а **потеря оговорки**: число остаётся, а его граница
        // исчезает.
        //
        // `enteredAt` — когда запись СДЕЛАЛИ, в отличие от `date`,
        // когда случилось. Без него «отметили вечером за утро»
        // перестаёт быть различимым.
        var isDayOnly: Bool?
        var enteredAt: Date?
        /// Кто поправил запись.
        ///
        /// **Асимметрия, которая объясняет, как поле выпало.** Заведено
        /// оно с рассуждением «та же причина, что у `deletedBy`»
        /// (`LogEvent.swift:109`), и оба стоят в `проСемью` у сторожа
        /// локальных полей — то есть объявлены общими для семьи. Замер:
        ///
        /// ```
        ///             обмен (TogoShared/Sync)   снимок   писатель
        /// deletedBy          5 упоминаний        есть      есть
        /// editedBy           0                   нет       нет
        /// ```
        ///
        /// Проведён один из двух. **Рассуждение скопировалось, проводка
        /// нет** — а комментарий «та же причина, что у соседа» читается
        /// как «сделано так же». Находка `togo-1e` и `togo-16`,
        /// проверена этой сессией.
        var editedBy: String?
        /// Чем записали: экран, голос, виджет, разбор текста.
        ///
        /// Соблазн счесть это «про телефон» есть, и он ошибочный —
        /// так записано у сторожа локальных полей: это свойство ЗАПИСИ,
        /// и второму человеку оно говорит, насколько ей доверять.
        /// Пишется из `RecallWriter:67`, то есть у дозаписи текстом
        /// оно и есть главное: «это разобрано из фразы, а не нажато».
        var originRaw: String?
        /// На что собака отреагировала и с какого расстояния.
        ///
        /// Пишутся из `WalkMode:461-462` и `IncidentSheet:170-171` —
        /// это и есть то, ради чего инцидент заводят: «на что · как
        /// близко · что делал». Терять их при переносе значит оставить
        /// человеку запись «был инцидент» без единой детали, по которой
        /// он завёлся. Замер `togo-1e`, проверен этой сессией
        /// по писателям, а не по объявлению.
        var reactionTriggerRaw: String?
        var reactionDistanceRaw: String?
        // Ссылки на другие записи. Восстановимы в принципе, и только
        // здесь: `EventSnapshot` — единственный снимок, который несёт
        // `id`, значит после восстановления идентичности совпадают
        // и ссылка находит свою цель.
        var walkEventID: UUID?
        var careTaskID: UUID?
        var medicationID: UUID?
        var trainingSessionID: UUID?
    }

    struct WeightSnapshot: Codable, Sendable {
        var date: Date
        var kg: Double
    }

    struct CareTaskSnapshot: Codable, Sendable {
        var title: String
        var detail: String
        var intervalDays: Int
        var lastDone: Date?
        var categoryRaw: String
        var seasonStartMonth: Int?
        var seasonEndMonth: Int?
        var snoozeCount: Int
        // Добавлено 07.10.2026. Все опциональные: архивы, снятые раньше,
        // этих ключей не знают и обязаны читаться.
        //
        // **`scheduledDate` — это ДАТА ПРИВИВКИ**, и архив терял её
        // молча. Медкнижка собаки без дат прививок — не медкнижка:
        // ветеринару нужен именно день, а не «каждые 365 дней».
        var kindRaw: String?
        var scheduledDate: Date?
        var remindDaysBefore: Int?
        var streak: Int?
        /// Три поля шага 0 медицинского слоя, 07.10.2026.
        ///
        /// **`clinicName`, а не ссылка.** Клиника лежит корневым
        /// массивом `clinics`, и связь хранится одним концом — здесь.
        /// Имя, а не индекс: файл человек читает глазами, и «клиника
        /// № 3» в нём не значит ничего. Имя клиники — ключ группировки
        /// и в самой модели, то есть второй сущности не заводим.
        ///
        /// **`vaccineBatch` — номер партии.** Его спрашивают, когда
        /// у собаки реакция или когда партию отзывают, и спрашивают
        /// у того, кто привёл собаку сегодня, — а не у хозяйки.
        var clinicName: String?
        var vaccineBatch: String?
        var vaccineValidUntil: Date?
    }

    struct MedicationSnapshot: Codable, Sendable {
        var name: String
        var doseText: String
        var times: [Int]
        var fastingMinutes: Int
        /// Окно натощак ПЕРЕД дозой. Необязательное: архивы, снятые
        /// до появления поля, читаются как прежде, и при восстановлении
        /// окно «до» берётся симметричным — так же, как у схемы,
        /// которая его не заполняла. Терять половину правила молча
        /// нельзя: это лечение.
        var fastingBeforeMinutes: Int?
        var isPaused: Bool
        var prescriber: String?
        var cancelledAt: Date?
        var cancelledNote: String?
        var doses: [DoseSnapshot]
        // Добавлено 07.10.2026, тринадцать полей, все опциональные.
        //
        // **`unitRaw` — единица дозы.** Без неё «0,5» в восстановленной
        // схеме не значит ничего: половина таблетки, половина миллилитра
        // и половина капли — три разные дозы, и ошибка здесь это
        // не путаница в дневнике, а передозировка.
        //
        // `courseEnd`, `expiry`, `openedAt`, `shelfAfterOpenDays` —
        // срок курса и срок годности; `stock*`, `packAmount` — запас,
        // по которому считается «пора покупать». Всё это человек вводит
        // руками один раз, и восстановление возвращало ему пустые поля.
        var unitRaw: String?
        /// Сила одной единицы в микрограммах — **то, от чего считается
        /// доза лекарства**.
        ///
        /// Добавлено 09.10.2026. Про `unitRaw` строкой выше подумали
        /// отдельно и написали почему; про массу — нет, и она уезжала
        /// в архив нулём мест: `Backup` 0 · `BackupArchive` 0, при
        /// `doseText` 2 · 1 и `unitRaw` 4 · 3.
        ///
        /// > **Форма потери хуже, чем «поле пропало».** `doseText`
        /// > и единица снимок переживают, поэтому восстановленная запись
        /// > **выглядит полной**: «2 таблетки» без силы таблетки пройдёт
        /// > любую проверку на непустоту. Пустое поле человек заметит,
        /// > это — нет.
        ///
        /// И цена не в архиве, а у врача: `LabChartScreen` делает
        /// `compactMap(\.dailyMassMcg)`, а `nil` по доккомментарию
        /// `Care.swift` значит «масса **не введена**». После
        /// восстановления график молча утверждает про человека, что он
        /// не вводил то, что вводил, — то есть **винит его в нашей
        /// потере**.
        ///
        /// Исключением это не оправдать: `ArchiveParityTests` допускает
        /// исключение «с причиной и условием, при котором оно перестанет
        /// быть верным», а условия, при котором терять силу таблетки
        /// допустимо, не существует. Сторож и так был **красен** на этом
        /// поле с `43f05a5` — его не слышали, потому что за сутки
        /// ни один полный прогон не дошёл до конца.
        var massPerUnitMcg: Double?
        var minutesAfterMeal: Int?
        var dependsOnMeal: Bool?
        var doseSlots: [DoseSlot]?
        var courseEnd: Date?
        var expiry: Date?
        var openedAt: Date?
        var shelfAfterOpenDays: Int?
        var remindBeforeExpiry: Bool?
        var stockLeft: Int?
        var stockTotal: Int?
        var stockLeftAmount: Double?
        var packAmount: Double?
        var canGiveOutside: Bool?
        /// Номер назначения — шаг 0, 07.10.2026.
        ///
        /// Связывает схему лечения с бланком рецепта: его называют
        /// в аптеке, чтобы продлить, и в клинике, чтобы найти запись.
        /// У Стича таких бланков тридцать четыре.
        var prescriptionNumber: String?
    }

    struct DoseSnapshot: Codable, Sendable {
        var scheduledAt: Date
        var givenAt: Date?
        var givenBy: String?
        var cancelledAt: Date?
        var cancelReason: String?
        // Добавлено 07.10.2026, опциональные.
        //
        // **`skippedAt` и `skippedBy` — ПРОПУЩЕННАЯ доза**, и это факт
        // лечения, а не его отсутствие: врач спрашивает «сколько раз
        // пропустили», и архив отвечал «ни разу» вместо правды.
        // Отсутствие отметки и отметка «пропущено» — разные вещи,
        // и первая читается как «дали», пока вторая не восстановлена.
        var skippedAt: Date?
        var skippedBy: String?
        var claimedBy: String?
        var claimedAt: Date?

        /// Чего доза ждёт, если схема до неё ещё не доехала.
        ///
        /// Едет **только имя**, без `awaitedMedicationID`, и это
        /// решение, а не недосмотр: `Medication.id` в архив не идёт
        /// нарочно (`ArchiveParityTests`, «после восстановления это
        /// другая запись»). Восстановленный `awaitedMedicationID`
        /// указывал бы **в никуда** — и выглядел бы при этом валидным
        /// UUID, то есть хуже отсутствия.
        ///
        /// Сшивка в `SharedDiaryPayloads:962` смотрит пару
        /// «по id ИЛИ по имени»; после восстановления сработает имя.
        /// Добавлено 07.10.2026, `togo-1e`.
        var awaitedMedicationName: String?
    }

    struct TrainingStepSnapshot: Codable, Sendable {
        var cue: String
        var place: String
        var person: String
        var distanceMeters: Int
        var statusRaw: String
        var consecutiveGoodSessions: Int
        var order: Int
    }

    struct TrainingSessionSnapshot: Codable, Sendable {
        var startedAt: Date
        var durationSeconds: Int
        var cue: String
        var place: String
        var person: String
        var distanceMeters: Int
        var markDelaysMs: [Int]
        var successes: Int
        var attempts: Int
        var gramsUsed: Int
        var observationsRaw: [String]
        var countsTowardProgress: Bool
    }

    struct TripSnapshot: Codable, Sendable {
        var destination: String
        var startDate: Date
        var endDate: Date
        var transportRaw: String
        var travelHours: Double
        var lodging: String
        var participants: [String]
        var departureMinuteOfDay: Int
        var packedItems: [String]
    }

    struct MemberSnapshot: Codable, Sendable {
        var name: String
        var roleRaw: String
        var note: String?
        var isMe: Bool
        var customPermissionsRaw: [String]?
        var isOnDuty: Bool
        var dutyUntil: Date?
        var accessExpiresAt: Date?
        var acceptedAt: Date?
    }

    struct EpisodeSnapshot: Codable, Sendable {
        var startedAt: Date
        var endedAt: Date?
        var title: String
        var detail: String

        /// Когда был последний инцидент эпизода.
        ///
        /// **Держит КОНЕЦ эпизода, а не его историю.** `isOngoing`
        /// сравнивает `now − lastIncidentAt < 48 ч` (`Family:102`,
        /// `EpisodeLifetime:52`), а в `init` это поле равно `startedAt`.
        /// Значит у восстановленного эпизода тишина считалась бы
        /// **от начала, а не от последнего инцидента**: эпизод,
        /// у которого инциденты шли пять дней, объявился бы законченным
        /// задним числом.
        ///
        /// Это обратная сторона дефекта, который чинили утром: тогда
        /// эпизод не заканчивался никогда, здесь он кончался бы сразу.
        /// Добавлено 07.10.2026, `togo-1e`.
        var lastIncidentAt: Date?
    }

    /// Коротко для экрана: что именно уедет в файл.
    var summary: String {
        let events = dogs.reduce(0) { $0 + $1.events.count }
        return [
            String(localized: "\(dogs.count) собак"),
            String(localized: "\(events) записей"),
            String(localized: "\(members.count) человек"),
        ].joined(separator: " · ")
    }
}
