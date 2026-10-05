import Foundation
import SwiftData

/// Повторяющееся дело: когти, вычёсывание, антипаразитарка, прививка, взвешивание.
/// Всё это собирается в одну утреннюю сводку, а не в восемь отдельных напоминаний.
@Model
final class CareTask {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var kindRaw: String = CareKind.periodic.rawValue
    var categoryRaw: String = CareCategory.grooming.rawValue

    /// Для регулярного: раз в сколько дней.
    var intervalDays: Int = 30
    /// Для «по дате»: когда именно и за сколько дней предупредить.
    var scheduledDate: Date?
    var remindDaysBefore: Int = 14

    var lastDone: Date?
    /// Для ежедневного: сколько дней подряд делали. Не награда, а зеркало.
    var streak: Int = 0

    /// Сезонное само знает про сезон: капли от клещей молчат зимой.
    var seasonStartMonth: Int?
    var seasonEndMonth: Int?

    /// Отложенное дважды подсвечивается в сводке, но не переходит в тревогу.
    var snoozeCount: Int = 0

    /// Когда этот телефон в последний раз трогал дело ухода.
    /// Расписание ездит в общем дневнике с 23.09.2026: без него «план
    /// дня» у гостя пуст, и приглашение приводит в комнату без дел.
    var changedAt: Date = Date()

    var dog: Dog?

    init(
        title: String,
        detail: String,
        kind: CareKind = .periodic,
        intervalDays: Int = 30,
        category: CareCategory = .grooming,
        lastDone: Date? = nil,
        scheduledDate: Date? = nil
    ) {
        self.title = title
        self.detail = detail
        self.kindRaw = kind.rawValue
        self.intervalDays = intervalDays
        self.categoryRaw = category.rawValue
        self.lastDone = lastDone
        self.scheduledDate = scheduledDate
    }

    var kind: CareKind {
        get { CareKind(rawValue: kindRaw) ?? .periodic }
        set { kindRaw = newValue.rawValue }
    }

    var category: CareCategory {
        get { CareCategory(rawValue: categoryRaw) ?? .grooming }
        set { categoryRaw = newValue.rawValue }
    }

    // MARK: Когда

    /// Даты нет: для регулярного не знаем, когда делали, для «по дате»
    /// не назначен день. Это не просрочка — но и не молчание навсегда:
    /// такое дело видно в отдельной группе и просит поставить дату.
    ///
    /// Раньше здесь была дыра: дело без даты никогда не становилось сроком,
    /// то есть заведённое напоминание не напоминало вообще ни о чём.
    var needsDate: Bool {
        switch kind {
        case .daily: false
        case .periodic: lastDone == nil
        case .dated: scheduledDate == nil
        }
    }

    var isNeverDone: Bool { needsDate }

    var dueDate: Date? {
        switch kind {
        case .daily:
            return Calendar.current.startOfDay(for: .now)
        case .periodic:
            guard let lastDone else { return nil }
            return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastDone)
        case .dated:
            return scheduledDate
        }
    }

    func daysUntilDue(from date: Date = Date()) -> Int? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: date),
                                       to: calendar.startOfDay(for: dueDate)).day
    }

    func isDoneToday(on date: Date = Date()) -> Bool {
        guard let lastDone else { return false }
        return Calendar.current.isDate(lastDone, inSameDayAs: date)
    }

    func isInSeason(on date: Date = Date()) -> Bool {
        guard let start = seasonStartMonth, let end = seasonEndMonth else { return true }
        let month = Calendar.current.component(.month, from: date)
        return start <= end ? (month >= start && month <= end) : (month >= start || month <= end)
    }

    /// Просится ли на главный экран прямо сейчас.
    func isDue(on date: Date = Date()) -> Bool {
        guard isInSeason(on: date) else { return false }
        switch kind {
        case .daily:
            return !isDoneToday(on: date)
        case .periodic:
            guard let days = daysUntilDue(from: date) else { return false }
            return days <= 0
        case .dated:
            guard let days = daysUntilDue(from: date) else { return false }
            return days <= remindDaysBefore
        }
    }

    /// Просрочено по-настоящему — это только про даты и регулярное.
    /// У ежедневного просрочки нет: пропущенный день не долг.
    func isOverdue(on date: Date = Date()) -> Bool {
        guard kind != .daily, isInSeason(on: date), let days = daysUntilDue(from: date) else { return false }
        return days < 0
    }

    /// Что написать в строке справа. Одна фраза на все три сорта ухода.
    func statusText(on date: Date = Date()) -> String {
        guard isInSeason(on: date) else { return String(localized: "вне сезона") }
        switch kind {
        case .daily:
            if isDoneToday(on: date) { return streak > 1 ? String(localized: "\(Fmt.days(streak)) подряд") : String(localized: "сегодня сделали") }
            return streak > 1 ? String(localized: "серия \(Fmt.days(streak))") : String(localized: "сегодня")
        case .periodic:
            guard let days = daysUntilDue(from: date) else { return String(localized: "когда делали?") }
            if days < 0 { return String(localized: "просрочено на \(Fmt.days(-days))") }
            if days == 0 { return String(localized: "сегодня") }
            if days == 1 { return String(localized: "завтра") }
            return String(localized: "через \(Fmt.days(days))")
        case .dated:
            guard let days = daysUntilDue(from: date) else { return String(localized: "когда делали?") }
            if days < 0 { return String(localized: "просрочено") }
            if days == 0 { return String(localized: "сегодня") }
            return Fmt.shortDay(dueDate ?? date)
        }
    }

    /// Отметить сделанным. Для ежедневного ведёт серию, для «по дате»
    /// двигает дату на следующий раз.
    func markDone(at date: Date = Date()) {
        if kind == .daily {
            let calendar = Calendar.current
            if let lastDone, let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(lastDone, inSameDayAs: yesterday) {
                streak += 1
            } else if !isDoneToday(on: date) {
                streak = 1
            }
        }
        if kind == .dated, let scheduled = scheduledDate, intervalDays > 0 {
            scheduledDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: scheduled)
        }
        lastDone = date
        snoozeCount = 0
    }

    /// Отменить отметку.
    ///
    /// Отметили не то — обычное дело: сработал свайп, зубы почистил
    /// кто-то другой, прививку перенесли. Без отката отметка о прививке
    /// сдвигала дату на год вперёд, и вернуть её было нельзя ничем,
    /// кроме как завести напоминание заново.
    func undoDone(previousDone: Date?) {
        if kind == .dated, let scheduled = scheduledDate, intervalDays > 0 {
            scheduledDate = Calendar.current.date(byAdding: .day, value: -intervalDays,
                                                  to: scheduled)
        }
        if kind == .daily {
            streak = max(0, streak - 1)
        }
        lastDone = previousDone
    }
}

/// Схему лечения меняет только владелец. Остальные видят и исполняют.
@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var doseText: String = ""
    /// Минуты от полуночи.
    var times: [Int] = []

    /// Расписание с количеством на каждое время.
    ///
    /// **Почему слотом, а не вторым массивом рядом с `times`.** Экран
    /// запаса показывает «½ утром, 1 вечером» — то есть количество
    /// привязано к часу, а не к препарату. Два параллельных массива
    /// («времена» и «количества») разъезжаются длинами молча, и тогда
    /// половина таблетки приземляется на чужой час. У слота
    /// разъезжаться нечем: час и количество лежат в одной записи.
    ///
    /// Пусто — значит расписание ведётся прежним способом, по `times`
    /// с количеством 1. Читать это поле напрямую не надо: `schedule`
    /// ниже отвечает за обе формы сразу.
    var doseSlotsData: [DoseSlot] = []

    /// Таблетки, миллилитры или «доза» без единицы.
    ///
    /// Капли считаются в мл и списываются дробно; таблетки бывают
    /// половинками. Без единицы «осталось 7» ничего не значит:
    /// семь таблеток — это неделя, семь миллилитров — один приём.
    var unitRaw: String = MedUnit.tab.rawValue

    /// Окно натощак после дозы: еда внутри него мешает всасыванию.
    var fastingMinutes: Int = 0

    /// Окно натощак ПЕРЕД дозой: к приёму желудок должен быть пустым.
    ///
    /// Половина правила, которой в модели не было. «Натощак» — это
    /// про пустой желудок, а пустым он бывает ДО таблетки, не после.
    /// Схема «покормили в 20:55, таблетка в 21:00» проходила прежнюю
    /// проверку целиком: окно после дозы соблюдено, а сама доза выпита
    /// на полный желудок.
    var fastingBeforeMinutes: Int = 0

    /// Сколько нельзя кормить перед дозой на самом деле.
    ///
    /// **Ноль у старой схемы читается как «столько же, сколько после»,
    /// и это исправление, а не догадка.** Натощак без окна «до» не
    /// бывает: доза сразу после еды не натощак по определению. Схемы,
    /// заведённые до появления поля, физически не могли его заполнить,
    /// и отдавать по ним «кормить можно» значило бы отвечать неверно
    /// там, где ответ известен.
    ///
    /// Явный ноль поставить всё же можно — через `fastingBeforeMinutes`
    /// у схемы, у которой `fastingMinutes` тоже ноль: тогда лекарство
    /// не натощак вовсе, и запирать нечего.
    var fastingBefore: Int { fastingBeforeMinutes > 0 ? fastingBeforeMinutes : fastingMinutes }

    /// Доза с условием: открывается через N минут после еды.
    ///
    /// Инсулин колют не по часам, а после того, как собака поела —
    /// иначе сахар падает в пустой желудок. Такая доза стоит в плане дня
    /// замком: отметить её раньше нельзя, а таймер стартует сам от
    /// отметки еды. Не поела — укол не открывается вовсе, и это не сбой,
    /// а вопрос к врачу.
    ///
    /// Ноль — обычная доза по часам.
    var minutesAfterMeal: Int = 0

    /// Есть ли у дозы условие по еде.
    var dependsOnMeal: Bool { minutesAfterMeal > 0 }
    var isPaused: Bool = false

    /// Сколько таблеток осталось и сколько было в пачке.
    ///
    /// Дыра, которой не было в списке: пропуски чаще случаются не
    /// из забывчивости, а потому что таблетки кончились в пятницу
    /// вечером. Счёт живёт на отметках приёма — отдельного учёта вести
    /// не надо, минус одна с каждой отметкой.
    ///
    /// Ноль в `stockTotal` значит «не считаем»: навязывать учёт тому,
    /// кто покупает по коробке в год, незачем.
    var stockLeft: Int = 0
    var stockTotal: Int = 0

    /// Тот же запас дробно: половинки таблеток и миллилитры.
    ///
    /// **Почему новое поле, а не смена типа у `stockLeft`.** Int → Double
    /// — это смена типа под уже отгруженной формой, а `.lightweight`
    /// выводит добавление поля и не выводит превращение. Шесть розданных
    /// сборок несут `stockLeft: Int`; сменить ему тип значило бы увести
    /// их хранилище в память молча.
    ///
    /// `nil` — значит дробный учёт этому препарату не заводили, и правду
    /// говорит целый `stockLeft`. Читать надо `remaining` и `packSize`
    /// ниже: они отвечают за обе формы, как `fastingBefore` отвечает
    /// за окно натощак у схем до и после появления поля.
    var stockLeftAmount: Double?
    var packAmount: Double?

    /// Курс до какого числа. `nil` — курс бессрочный.
    ///
    /// **Поле, которого не хватало уже написанному коду, а не новая
    /// функция.** `PillSupply.shortfallDays` считает нехватку на курс
    /// и покрыт тестами, но тесты передают дату курса сами, аргументом,
    /// — а экран передать её не может: в модели её нет. Значит строка
    /// «курс идёт до такого-то, не хватит столько-то» не показывалась
    /// никому ни разу. Замер togo-9e, 05.10.2026.
    var courseEnd: Date?

    /// Годен до — с упаковки. Месяц и год; день в сроке годности
    /// лекарств не печатают, поэтому здесь конец месяца.
    var expiry: Date?

    /// Когда вскрыли флакон. `nil` — ещё не вскрыт.
    ///
    /// **Это НЕ срок годности, и путать их нельзя.** У капель после
    /// вскрытия свой срок, обычно короче остатка годности, и шторка
    /// «Купил» переключает одно в другое тумблером «Сразу вскрыл».
    /// Одним полем разница потерялась бы молча — и проявилась бы
    /// у человека с открытым флаконом, то есть там, где цена ошибки
    /// измеряется дозой.
    var openedAt: Date?

    /// Сколько дней годен после вскрытия. Ноль — срок после вскрытия
    /// не задан, и тогда действует только `expiry`.
    var shelfAfterOpenDays: Int = 0

    /// Напоминать о покупке за месяц до конца срока годности.
    var remindBeforeExpiry: Bool = false

    /// Можно ли дать этот препарат на улице.
    ///
    /// Нужно не «Запасу», а прогулке: в шторке «Просится» и в режиме
    /// «На улице» появляется строка «Дал», если доза попадает в ±30 минут
    /// от выхода. Таблетку натощак на улице не дают, капли в глаз — дают.
    var canGiveOutside: Bool = false

    var prescriber: String?
    var cancelledAt: Date?
    var cancelledNote: String?

    /// Когда этот телефон в последний раз трогал схему.
    /// Схемы ездят с 23.09.2026: дозы ездили и раньше, а препарат,
    /// к которому они относятся, — нет, и у гостя приёмы были
    /// без названия.
    var changedAt: Date = Date()

    var dog: Dog?

    @Relationship(deleteRule: .cascade, inverse: \DoseRecord.medication)
    var dosesStorage: [DoseRecord]?

    init(name: String, doseText: String, times: [Int], fastingMinutes: Int = 0) {
        self.name = name
        self.doseText = doseText
        self.times = times
        self.fastingMinutes = fastingMinutes
    }

    // CloudKit требует опциональных связей — см. пояснение в Dog.
    var doses: [DoseRecord] { dosesStorage ?? [] }

    var scheduleSummary: String {
        let clock = times.sorted().map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: String(localized: " и "))
        return fastingMinutes > 0 ? String(localized: "\(clock) · натощак \(fastingMinutes) мин") : clock
    }

    var unit: MedUnit {
        get { MedUnit(rawValue: unitRaw) ?? .tab }
        set { unitRaw = newValue.rawValue }
    }

    /// Расписание в одной форме — безразлично, как оно записано.
    ///
    /// Схемы, заведённые до появления слотов, физически не могли их
    /// заполнить: у них есть только `times`, и количество там одно
    /// на каждый час. Отдавать по ним пустое расписание значило бы
    /// сказать «доз нет» там, где они есть, — то же, чем был опасен
    /// ноль у окна натощак.
    var schedule: [DoseSlot] {
        doseSlotsData.isEmpty
            ? times.sorted().map { DoseSlot(minuteOfDay: $0, quantity: 1) }
            : doseSlotsData.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    /// Сколько осталось — дробно, если дробный учёт заведён.
    var remaining: Double { stockLeftAmount ?? Double(stockLeft) }

    /// Сколько в упаковке или флаконе — дробно, если заведено.
    var packSize: Double { packAmount ?? Double(stockTotal) }

    /// Сколько уходит в день по расписанию.
    var dailyUse: Double { schedule.map(\.quantity).reduce(0, +) }

    /// Поставить остаток — обе формы разом.
    ///
    /// **Почему методом в модели, а не строкой на экране.** Запас
    /// хранится в двух полях: целое `stockLeft` для розданных сборок
    /// и дробное `stockLeftAmount` для половинок и миллилитров. Читается
    /// он через `remaining`, то есть **из дробного, когда оно есть**.
    /// Значит писатель, тронувший только `stockLeft`, нажимается
    /// и не меняет ничего: человек жмёт «+ 30 шт», видит прежнее число
    /// и жмёт снова.
    ///
    /// Поймал togo-9e на кнопке «+ 30 шт» 05.10.2026, починил на экране
    /// — и сказал вслух, что писателей будет больше одного: шторка
    /// «Купил» с кадра 33 пополняет запас у всей семьи. Правило,
    /// живущее на одной поверхности из двух, у нас уже стоило дня
    /// трижды, поэтому оно здесь, а не там.
    ///
    /// Целое поле получает **пол** от дробного: половина таблетки,
    /// невидимая старой сборке, лучше неверной целой.
    /// Возвращает прежний остаток — чтобы вызывающий мог его вернуть.
    ///
    /// **Откат обязан быть дробным.** У `DoseScheduler.markGiven` откат
    /// снимается до списания и возвращается, если сохранение не прошло:
    /// там `try?` стоил бы второй дозы. Целочисленный снимок вернул бы
    /// не то, что было, — и ошибка легла бы на запас лекарства.
    /// Замечание togo-9e, 05.10.2026, до коммита.
    @discardableResult
    func setStock(_ сколько: Double) -> Double {
        let прежний = remaining
        let итог = max(0, сколько)
        stockLeftAmount = итог
        stockLeft = Int(итог.rounded(.down))
        return прежний
    }

    /// Пополнить запас на столько-то — для кнопки «Купил».
    @discardableResult
    func addStock(_ сколько: Double) -> Double { setStock(remaining + сколько) }

    /// Списать дозу — ровно столько, сколько стоит в слоте.
    ///
    /// Половина таблетки списывает 0,5, а не одну: иначе запас
    /// кончается на бумаге вдвое раньше, человек покупает лишнее
    /// и перестаёт верить числу.
    @discardableResult
    func takeDose(_ сколько: Double) -> Double { setStock(remaining - сколько) }

    /// Вернуть дозу в пачку — отметку сняли.
    ///
    /// Потолок берётся у `packSize`, а не у `stockTotal`: у препарата
    /// с дробным учётом целое поле мёртво, и потолок пришёл бы не оттуда.
    @discardableResult
    func returnDose(_ сколько: Double) -> Double {
        let потолок = packSize > 0 ? packSize : .greatestFiniteMagnitude
        return setStock(min(потолок, remaining + сколько))
    }

    /// Сколько даёт доза, назначенная на это время.
    ///
    /// Слот ищется по минуте суток, а не по дате: расписание суточное,
    /// а доза — конкретного дня. Нет слота на этот час — доза считается
    /// за единицу: так ведут себя все схемы, заведённые до появления
    /// слотов, и у них это верно.
    func quantity(at scheduled: Date, calendar: Calendar = .current) -> Double {
        let части = calendar.dateComponents([.hour, .minute], from: scheduled)
        let минута = (части.hour ?? 0) * 60 + (части.minute ?? 0)
        return schedule.first { $0.minuteOfDay == минута }?.quantity ?? 1
    }

    /// До какого дня препарат годен на самом деле.
    ///
    /// Два срока, и побеждает ближний: вскрытый флакон портится раньше,
    /// чем кончается срок на упаковке, и наоборот — вскрытый за месяц
    /// до конца годности живёт до конца годности, а не дольше.
    func goodUntil(calendar: Calendar = .current) -> Date? {
        let после = openedAt.flatMap { opened in
            shelfAfterOpenDays > 0
                ? calendar.date(byAdding: .day, value: shelfAfterOpenDays, to: opened)
                : nil
        }
        return [expiry, после].compactMap { $0 }.min()
    }
}

/// Один приём в расписании: час и сколько дать.
///
/// `quantity` дробное, потому что половина таблетки — обычное
/// назначение, а капли мерят миллилитрами. Единица у препарата
/// одна (`Medication.unit`), поэтому в слоте её нет: иначе два слота
/// одного препарата могли бы разойтись в единицах, а такого
/// назначения не бывает.
nonisolated struct DoseSlot: Codable, Hashable, Sendable {
    /// Минуты от полуночи — та же мера, что у `Medication.times`.
    var minuteOfDay: Int
    var quantity: Double

    var clock: String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

@Model
final class DoseRecord {
    var id: UUID = UUID()
    var scheduledAt: Date = Date()
    var givenAt: Date?
    var givenBy: String?
    /// «Беру на себя» с TTL 45 минут снимает двойную дозу.
    var claimedBy: String?
    var claimedAt: Date?
    /// Отмена дозы оставляет запись об отмене, а не стирает её.
    var cancelledAt: Date?
    var cancelReason: String?
    /// Когда этот телефон в последний раз трогал отметку. См. `LogEvent`.
    var changedAt: Date = Date()

    /// Дозу решили пропустить.
    ///
    /// Пропуск — это запись, а не пустота: врач спрашивает именно про
    /// него, а иначе в истории непонятно, забыли отметить или правда
    /// не дали.
    var skippedAt: Date?
    var skippedBy: String?

    var medication: Medication?

    /// Чего доза ждёт, если схема ещё не приехала.
    ///
    /// Связь `medication` — это ссылка на объект, и у неё нет памяти:
    /// ничья доза не помнит, чьей она хотела быть. Пока схемы не ездили,
    /// это было неважно — их искали по имени в момент приёма и на этом
    /// всё. Теперь схема может приехать ПОСЛЕ своих доз (обмен включили
    /// посреди курса), и без этих двух полей подобрать их нечем:
    /// ничья доза на экране не показывается вовсе, то есть второй
    /// человек видит приём открытым и даёт вторую таблетку.
    ///
    /// Заполняется только у приехавших доз и только когда схема
    /// не нашлась. Своя доза всегда заводится со схемой в руках.
    var awaitedMedicationID: UUID?
    var awaitedMedicationName: String?

    init(scheduledAt: Date) {
        self.scheduledAt = scheduledAt
    }

    static let claimTTL: TimeInterval = 45 * 60

    var isGiven: Bool { givenAt != nil }
    var isSkipped: Bool { skippedAt != nil }

    func claimIsActive(at date: Date = Date()) -> Bool {
        guard let claimedAt else { return false }
        return date.timeIntervalSince(claimedAt) < Self.claimTTL
    }

    /// Лестница эскалации: т−10 дежурному, т+30 со-владельцам, т+60 всем и запись «пропуск».
    ///
    /// **Пропуск снимает лестницу так же, как приём.** Раньше здесь
    /// не было `isSkipped`, и «пропустить» не гасило тревогу: человек
    /// принимал решение, записывал его — а красное «не отмечена»
    /// оставалось и через сутки, и через неделю. Лестница существует
    /// ровно для того случая, когда решения ещё НЕТ; пропуск — это
    /// решение и запись, врач спрашивает именно про него.
    func escalationStage(at date: Date = Date()) -> Int {
        if isGiven || isSkipped || cancelledAt != nil { return 0 }
        let minutes = date.timeIntervalSince(scheduledAt) / 60
        if minutes >= 60 { return 3 }
        if minutes >= 30 { return 2 }
        if minutes >= -10 { return 1 }
        return 0
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var kg: Double = 0
    var dog: Dog?

    init(date: Date = Date(), kg: Double) {
        self.date = date
        self.kg = kg
    }
}
