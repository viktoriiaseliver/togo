import Foundation

/// Разбор дозаписи, написанной словами.
///
/// Человек пишет всё целиком, своими словами и задним числом:
/// «13.09.26 был понос», «кормили 3 раза в день с 04.09 по 20.09»,
/// «гуляли примерно каждый день по 4 часа с 04.09 по 20.09».
///
/// **Правилами, а не моделью.** Сети у приложения нет — это красная линия
/// продукта, и отправлять текст о собаке наружу ради разбора нельзя.
/// Значит разбор целиком здесь: даты, диапазоны, виды, количества.
///
/// **Непонятое не молчит.** Строка, которую разобрать не вышло, возвращается
/// как `.notUnderstood` вместе с исходным текстом — её показывают человеку
/// и дают поправить руками. Тихо проглотить строку нельзя: это вернёт ровно
/// ту дыру в истории, ради закрытия которой всё и делается.
///
/// **Период — не семнадцать прогулок.** «Каждый день по 4 часа с 04.09
/// по 20.09» превращается в одну запись-период, а не в семнадцать событий
/// с придуманным временем: придуманное время в выгрузке врачу стало бы
/// неотличимо от измеренного. Разбор — `docs/ТЗ-дозапись-задним-числом.md`.
///
/// # Мест вызова ноль, и это НЕ недоделка — макет задал другую форму
///
/// Замер 08.10.2026 на `ca8b276`: `RecallParser.` вне `TogoTests/`
/// не встречается нигде, кроме подписи типа у `RecallWriter`
/// (строка 35 его файла).
///
/// Имя соседа здесь написано БЕЗ точки после него, и это не стиль.
/// `SingleDoorTests.дозаписьМертва` ищет подстроку «`RecallWriter`»
/// с точкой по всем `.swift` в `Togo`, `TogoShared`, `TogoWidgets`
/// — включая комментарии. Первая редакция этого абзаца ссылалась
/// на «RecallWriter·swift:35» с точкой и **покрасила бы сторожа
/// прозой**: он доложил бы «дозапись подключили: RecallParser.swift».
/// Поймано до коммита; сам сторож после этого научен вырезать
/// комментарии — см. его голову.
/// Голова этого файла до сегодня говорила только о том, ЧТО он делает,
/// — то есть читалась как обычный долг, и следующий подключил бы его
/// законно. Причина записана здесь, потому что её читают здесь.
///
/// Форму входа задаёт `Togo ФИНАЛ v2`, раздел **«10 · H1 · Перерыв
/// в записях»** (выгрузка дизайна 08.10 в `~/Downloads/Дневник собаки
/// Togo`, в git её не кладём — правда дизайна уедет в Figma). Там
/// два кадра:
///
/// - «Записей нет с 3 сентября» · 18 дней · кнопка «Дозаписать,
///   что помните»;
/// - форма **«Дозапись по дням»**: подзаголовок «3 — 20 сентября ·
///   18 дней», три тумблера («Кормили — как обычно · 2 раза»,
///   «Доза — по схеме · 8:00 и 20:00», «Выходы — примерно 4 в день»),
///   чипы «Насколько точно» (`точно` · `примерно`, выбрано
///   «примерно»), список «Отдельные дни» («Жидкий стул · 13 сент ·
///   с заметкой», «Добавить день»), итог «Запишется 36 кормлений,
///   36 доз и ≈ 72 выхода» и кнопка «Записать 18 дней».
///
/// **Экрана, на котором человек пишет словами, в макете нет вовсе.**
/// Измерено по тексту выгрузки: «текстом» — 0 вхождений, «своими
/// словами» — 0, «разбор» — 0; «чат» целым словом — ни одного (все
/// шесть слов с этим корнем — «Начать», «Переключатель», «Получать»,
/// «скачать»).
///
/// Значит подключить разбор текста «как в ТЗ» — построить поверхность,
/// которой дизайн не просил. ТЗ от 21.09 кончается словами «формата
/// самого экрана чата: макета нет, и придумывать его в коде нельзя».
/// За семнадцать дней макет появился, и форма в нём другая — разбор
/// ТЗ против макета лежит в `docs/ТЗ-дозапись-задним-числом.md`,
/// раздел «Что изменилось с 21.09».
///
/// Что из этого файла живо при форме из макета: `day(in:)`,
/// `range(in:)` и `Period.byDay()` — датами и разворотом периода
/// по дням форма пользуется. Что не нужно: `kind(in:)`, `stool(in:)`,
/// `grams(in:)`, `timesPerDay(in:)` — вид события и количество
/// в макете выбирает тумблер, а не слово в тексте. Удалять их
/// не надо: решение «чата нет» принято дизайном, а не продуктом,
/// и `RecallDictionary` сторожит их на трёх языках.
nonisolated enum RecallParser {

    // MARK: Что получается на выходе

    public struct Moment: Equatable {
        public var kind: LogKind
        public var at: Date
        public var grams: Int?
        public var stool: StoolForm?
        /// Сколько раз за день, если сказано «3 раза».
        public var times: Int?
    }

    public struct Period: Equatable {
        public var kind: LogKind
        public var from: Date
        public var to: Date
        /// Сколько раз в день — «кормили 3 раза в день».
        public var timesPerDay: Int?
        /// Сколько длилось за раз — «по 4 часа».
        public var durationSeconds: Int?

        /// Сколько суток покрывает период, включительно.
        public var days: Int {
            let calendar = Calendar.current
            let a = calendar.startOfDay(for: from), b = calendar.startOfDay(for: to)
            return (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        }

        /// Разложить период по дням — по одному черновику на сутки.
        ///
        /// **Это не то же самое, что выдумать семнадцать записей.** Черновики
        /// показываются человеку списком: он видит каждый день отдельно,
        /// правит дату, дописывает своими словами («в среду почти не гуляли»)
        /// и выбрасывает лишние. В базу уходит только то, что он подтвердил.
        ///
        /// Час не подставляется **ничем**: у каждого дня `date` — начало
        /// суток, а `isDayOnly` говорит, что точнее не известно. Придуманное
        /// «14:02» в выгрузке врачу стало бы неотличимо от измеренного,
        /// а «13 сентября» — честная правда.
        public func byDay() -> [DayDraft] {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: from)
            return (0..<max(days, 0)).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start)
                else { return nil }
                return DayDraft(kind: kind, day: day,
                                timesPerDay: timesPerDay, durationSeconds: durationSeconds)
            }
        }
    }

    /// Один день из разложенного периода — до того, как человек его
    /// подтвердил. Дату можно поменять, описание — дописать.
    public struct DayDraft: Equatable {
        public var kind: LogKind
        /// Начало суток. Часа нет и не будет: см. `Period.byDay()`.
        public var day: Date
        public var timesPerDay: Int?
        public var durationSeconds: Int?
        /// Своими словами — то, что человек допишет к этому дню.
        /// Пусто, пока он не написал.
        public var note: String?
        /// Снято галочкой: день был, а записи по нему не нужно.
        public var isExcluded: Bool = false
    }

    public enum Line: Equatable {
        case moment(Moment)
        case period(Period)
        /// Разобрать не вышло. Текст возвращается как есть — человеку.
        case notUnderstood(String)
        /// Язык заведён, а слов разбора для него ещё нет.
        ///
        /// Отдельно от `notUnderstood`, и это не педантизм.
        /// `RecallDictionary.пустой` обещает: «человеку об этом надо
        /// сказать **иначе**, чем „не понял"» — а разбор отвечал
        /// одинаково. Разница для человека большая: «не понял»
        /// значит «перепиши», а «этот язык ещё не разбираю» значит
        /// «переписывать бесполезно, дело не в тебе».
        case языкНеРазбирается(String)
    }

    // MARK: Разбор

    /// Разобрать текст целиком. Каждая непустая строка — отдельная запись.
    public static func parse(_ text: String, today: Date = Date()) -> [Line] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line(from: $0, today: today) }
    }

    static func line(from raw: String, today: Date) -> Line {
        let text = RecallDictionary.нормализовать(raw)
        let словарь = RecallDictionary.текущий
        // Сначала — есть ли чем разбирать вообще.
        guard !словарь.пустой else { return .языкНеРазбирается(raw) }
        guard let kind = kind(in: text, словарь: словарь) else { return .notUnderstood(raw) }

        if let (from, to) = range(in: text, today: today, словарь: словарь) {
            return .period(Period(kind: kind, from: from, to: to,
                                  timesPerDay: timesPerDay(in: text, словарь: словарь),
                                  durationSeconds: duration(in: text, словарь: словарь)))
        }
        guard let at = day(in: text, today: today, словарь: словарь) else {
            return .notUnderstood(raw)
        }
        return .moment(Moment(kind: kind, at: at,
                              grams: grams(in: text, словарь: словарь),
                              stool: stool(in: text, словарь: словарь),
                              times: timesPerDay(in: text, словарь: словарь)))
    }

    // MARK: Вид записи

    /// Слова подобраны по тому, как пишут в переписке, а не по названиям
    /// в интерфейсе: «был понос», а не «стул, форма: лужа».
    /// Оставлено ради тестов и старых вызовов: словарь теперь живёт
    /// в `RecallDictionary`, по языкам.
    static var words: [(LogKind, [String])] { RecallDictionary.русский.основы }

    static func kind(in text: String, словарь: RecallDictionary = .текущий) -> LogKind? {
        // Порядок важен: «понос» встречается раньше «дал», и строка
        // «13.09 дали таблетку, был понос» — про две разные вещи.
        // Пока берём первую найденную и честно признаём ограничение:
        // две записи в одной строке не разбираются.
        let текст = RecallDictionary.нормализовать(text)
        for (kind, stems) in словарь.основы
        where stems.contains(where: { текст.contains(RecallDictionary.нормализовать($0)) }) {
            return kind
        }
        return nil
    }

    // MARK: Даты

    static let dayMonth = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})[.\/](\d{1,2})(?:[.\/](\d{2,4}))?\b"#
    )

    /// Одна дата: «13.09.26», «13.09», «вчера», «сегодня», «позавчера».
    static func day(in text: String, today: Date,
                    словарь: RecallDictionary = .текущий) -> Date? {
        let calendar = Calendar.current
        let текст = RecallDictionary.нормализовать(text)
        func есть(_ слова: [String]) -> Bool {
            слова.contains { текст.contains(RecallDictionary.нормализовать($0)) }
        }
        // Порядок важен: «позавчера» содержит «вчера».
        if есть(словарь.позавчера) {
            return calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))
        }
        if есть(словарь.вчера) {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
        }
        if есть(словарь.сегодня) { return calendar.startOfDay(for: today) }
        return dates(in: text, today: today).first
    }

    /// Диапазон «с 04.09 по 20.09». Нужны обе даты и слово-связка:
    /// две даты подряд без «с … по» — это две записи, а не период.
    static func range(in text: String, today: Date,
                      словарь: RecallDictionary = .текущий) -> (Date, Date)? {
        let текст = RecallDictionary.нормализовать(text)
        func есть(_ слова: [String]) -> Bool {
            слова.contains { слово in
                let с = RecallDictionary.нормализовать(слово)
                return текст.contains(с) || текст.hasPrefix(с.trimmingCharacters(in: .whitespaces) + " ")
            }
        }
        guard есть(словарь.началоПериода), есть(словарь.конецПериода) else { return nil }
        let found = dates(in: text, today: today)
        guard found.count >= 2 else { return nil }
        let sorted = found.sorted()
        return (sorted.first!, sorted.last!)
    }

    static func dates(in text: String, today: Date) -> [Date] {
        guard let dayMonth else { return [] }
        let calendar = Calendar.current
        let ns = text as NSString
        return dayMonth.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> Date? in
                func part(_ i: Int) -> Int? {
                    guard match.range(at: i).location != NSNotFound else { return nil }
                    return Int(ns.substring(with: match.range(at: i)))
                }
                guard let d = part(1), let m = part(2), (1...31).contains(d), (1...12).contains(m)
                else { return nil }
                var year = calendar.component(.year, from: today)
                if let y = part(3) { year = y < 100 ? 2000 + y : y }
                var components = DateComponents()
                components.year = year; components.month = m; components.day = d
                guard let date = calendar.date(from: components) else { return nil }
                // Дата без года, оказавшаяся в будущем, — это прошлый год:
                // «31.12» в январе значит прошлый декабрь, а не следующий.
                if part(3) == nil, date > today {
                    return calendar.date(byAdding: .year, value: -1, to: date)
                }
                return date
            }
    }

    // MARK: Количества

    static func number(in text: String, after unit: [String]) -> Int? {
        for u in unit {
            guard let r = text.range(of: #"(\d+)\s*"# + u, options: .regularExpression) else { continue }
            let digits = text[r].prefix { $0.isNumber || $0 == " " }
            if let n = Int(digits.trimmingCharacters(in: .whitespaces)) { return n }
        }
        return nil
    }

    // Единицы и формы стула — из словаря, как и остальные основы.
    //
    // Зашитыми литералами они попали в каталог и были переведены:
    // `г\\b` стал `g\\b`, «час» — «година». Перевод при этом
    // не использовался ничем: разбор брал литералы. Та же форма, что
    // у `Text(строка)`, — перевод существует, выглядит работающим
    // и не значит ничего.

    static func grams(in text: String,
                      словарь: RecallDictionary = .текущий) -> Int? {
        number(in: text, after: словарь.граммы)
    }

    static func timesPerDay(in text: String,
                            словарь: RecallDictionary = .текущий) -> Int? {
        number(in: text, after: словарь.разы)
    }

    static func duration(in text: String,
                         словарь: RecallDictionary = .текущий) -> Int? {
        if let hours = number(in: text, after: словарь.часы) { return hours * 3600 }
        if let minutes = number(in: text, after: словарь.минуты) { return minutes * 60 }
        return nil
    }

    // MARK: Стул

    static func stool(in text: String,
                      словарь: RecallDictionary = .текущий) -> StoolForm? {
        let приведённый = RecallDictionary.нормализовать(text)
        for (форма, основы) in словарь.формыСтула
        where основы.contains(where: { приведённый.contains(RecallDictionary.нормализовать($0)) }) {
            return форма
        }
        return nil
    }
}
