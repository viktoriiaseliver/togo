import Foundation
import SwiftData

// Медицинский слой: анализы, визиты, диагнозы, назначения.
// ТЗ — `docs/ТЗ-медицинский-слой.md` §2. Поля выведены из настоящей
// медкнижки Стича: 127 анализов, 34 рецепта, восемь замеров щитовидной
// с часами после приёма. Что встречается в карте меньше трёх раз —
// в заметку, а не в поле, как требует ТЗ.
//
// **Вычисляемые правила здесь не дублируются.** Отклонение от нормы,
// терапевтический коридор и часы от дозы живут в `LabNorm`,
// `LabSampleTiming` и `ControlWindow`: два правила на одну мысль
// расходятся на второй правке, и у Togo это записано трижды.

/// Результат анализа. Одна строка бланка — один показатель.
///
/// **Почему строка, а не бланк.** В карте Стича один отчёт несёт
/// до двадцати двух показателей (биохимия), и норма у каждого своя.
/// Храни бланк — и «Т4 ниже нормы» придётся выводить из массива
/// внутри записи, то есть завести вторую модель внутри первой.
/// Отчёт связывает строки номером: `reportNumber`.
@Model
final class LabResult {
    var id: UUID = UUID()

    /// Дата забора. Обязательна.
    var sampledOn: Date = Date()

    /// Время забора. **Обязательно при активном лечении**, и это
    /// требование врача, а не удобство: Кочубина 29.09.2026 написала
    /// «в направлении обязательно указать „левотироксин принят …
    /// часов назад“». Без него результат не интерпретируется —
    /// в карте есть случай, где бланк и счёт разошлись на полтора
    /// часа, и это изменило вывод.
    ///
    /// Пусто — значит не записано, и так и показывается. Подставлять
    /// «вероятно, утром» нельзя: `LabSampleTiming` отличает «не указано»
    /// от «лечения нет» отдельным случаем именно для этого.
    var sampledAt: Date?

    /// Лаборатория: IDEXX · Antech · клиника. Строкой, не справочником:
    /// лабораторий в карте четыре, и они не повторяются так, как клиники.
    var laboratory: String = ""

    /// Номер заказа или отчёта: `VF120682`, `337637858`, `22/08/26-1-0238`.
    /// Связывает строки одного бланка между собой.
    var reportNumber: String = ""

    /// Раздел бланка: гормоны · биохимия · общий анализ · бактериология.
    /// Нужен, чтобы список не смешивал несравнимое.
    var section: String = ""

    /// Показатель: «Т4 общий», «ТТГ», «мочевина».
    var indicator: String = ""

    // MARK: Значение

    /// Числовое значение. Пусто, если результат — предел прибора
    /// или текст (бактериология даёт описание, а не число).
    var value: Double?

    /// Значение ниже предела обнаружения: в карте есть `<0,1 нг/дл`.
    /// Это **не число 0,1**, и `LabNorm.Value.belowDetectionLimit`
    /// существует ровно для этого: записав пределом, получили бы
    /// тихо неверное число вместо видимо неизвестного.
    var belowLimit: Double?

    /// Значение выше предела обнаружения.
    var aboveLimit: Double?

    /// Текстовый результат там, где числа нет вовсе: «выделен штамм
    /// коагулазо-отрицательного стафилококка».
    var textValue: String?

    var unit: String = ""

    // MARK: Норма

    /// Низ и верх референса. Оба пусты — норма не указана, и
    /// `LabNorm.Reference.unknown` скажет «норма не указана», а не
    /// «в норме». ТЗ запрещает подставлять норму из интернета.
    var referenceLow: Double?
    var referenceHigh: Double?

    /// **Метод исследования — на ИЗМЕРЕНИИ, а не на показателе.**
    /// Решение `togo-05`, и довод его: показатель один и тот же,
    /// а метод у него менялся во времени. Свободный Т4 равновесным
    /// диализом не сравним с обычным — на него не влияют антитела.
    ///
    /// И требование, без которого поле бесполезно: **два значения
    /// разными методами нельзя рисовать одной линией и нельзя
    /// называть расхождением.** Поле без этого правила даёт график,
    /// на котором смена метода выглядит ухудшением.
    var method: String?

    /// **Отметка самой лаборатории** — `↑`, `↓` или «норма» с бланка.
    ///
    /// ТЗ требует, чтобы отклонение **считалось, а не вводилось**,
    /// и это выполнено: наш вердикт даёт `LabNorm`. Но отметка
    /// лаборатории — не наш вердикт, а **факт из документа**, и она
    /// хранится отдельно именно поэтому.
    ///
    /// Зачем: расхождение нашего счёта с отметкой бланка — **находка,
    /// а не ошибка**. В карте Стича референс Т4 менялся трижды
    /// (12,9–51,5 · 12,87–51,48 · 13–51), и лаборатория считала
    /// по своему. Храни только свой вердикт — и расхождение станет
    /// невидимым; храни только её — и вернёмся к «вводится».
    var labMark: String = ""

    /// Заметка с бланка: «на бланке Т+5ч, по счёту ≈3,5 ч».
    var note: String = ""

    var changedAt: Date = Date()
    var dog: Dog?

    init(sampledOn: Date = Date(),
         indicator: String = "",
         section: String = "",
         laboratory: String = "",
         reportNumber: String = "") {
        self.sampledOn = sampledOn
        self.indicator = indicator
        self.section = section
        self.laboratory = laboratory
        self.reportNumber = reportNumber
    }

    /// Референс в том виде, в каком его понимает `LabNorm`.
    ///
    /// Собирается здесь, а не во вью: иначе каждая поверхность соберёт
    /// свой, и «норма не указана» однажды превратится в «в норме».
    var reference: LabNorm.Reference {
        switch (referenceLow, referenceHigh) {
        case let (low?, high?): .range(low: low, high: high)
        case let (nil, high?): .upperBound(high)
        case let (low?, nil): .lowerBound(low)
        case (nil, nil): .unknown
        }
    }

    /// Значение в том виде, в каком его понимает `LabNorm`.
    /// Пусто — значит числового значения нет вовсе (текстовый
    /// результат), и спрашивать про отклонение нечего.
    var measuredValue: LabNorm.Value? {
        if let value { return .measured(value) }
        if let belowLimit { return .belowDetectionLimit(belowLimit) }
        if let aboveLimit { return .aboveDetectionLimit(aboveLimit) }
        return nil
    }
}

/// Визит к врачу. **Онлайн-консультация — такой же визит**, и это
/// решение из ТЗ: у Стича их две, и одна дала рабочую гипотезу
/// диагноза. Не влезет онлайн в модель — половина истории окажется
/// вне её.
@Model
final class VetVisit {
    var id: UUID = UUID()
    var date: Date = Date()

    /// Клиника из справочника. Связь, а не строка: в карте одиннадцать
    /// организаций, и без справочника «Vet Riviera» наберут двенадцатью
    /// способами, а группировка сломается — наш же класс про ключи.
    var clinic: Clinic?

    /// Врач строкой: врачей больше, чем клиник, и повторяются они реже.
    var doctor: String = ""

    /// Повод: осмотр · контроль · приём по острому · **онлайн**.
    var reasonRaw: String = VisitReason.checkup.rawValue

    /// Заключение. Длинный текст — в карте есть заключения на абзац.
    var conclusion: String = ""

    var changedAt: Date = Date()
    var dog: Dog?

    init(date: Date = Date(), doctor: String = "", reasonRaw: String = VisitReason.checkup.rawValue) {
        self.date = date
        self.doctor = doctor
        self.reasonRaw = reasonRaw
    }

    var reason: VisitReason {
        get { VisitReason(rawValue: reasonRaw) ?? .checkup }
        set { reasonRaw = newValue.rawValue }
    }
}

nonisolated enum VisitReason: String, Codable, CaseIterable, Sendable {
    case checkup      // осмотр
    case control      // контроль по назначению
    case acute        // приём по острому
    case online       // онлайн-консультация — такой же визит

    var title: String {
        switch self {
        case .checkup: String(localized: "осмотр")
        case .control: String(localized: "контроль")
        case .acute: String(localized: "по острому")
        case .online: String(localized: "онлайн")
        }
    }
}

/// Диагноз. **Три статуса, а не два** — требование ТЗ, и причина
/// в карте: одновременно живут подтверждённый диагноз и рабочая
/// гипотеза о его причине. Это разные вещи — по первому лечат,
/// по второй ищут.
@Model
final class Diagnosis {
    var id: UUID = UUID()

    /// Формулировка: «первичный гипотиреоз».
    var wording: String = ""

    var statusRaw: String = DiagnosisStatus.hypothesis.rawValue

    /// Дата постановки.
    var madeOn: Date = Date()

    /// Кем: врач и клиника.
    var madeBy: String = ""

    /// Чем подтверждён: номер отчёта анализа или дата визита.
    /// Строкой, а не связью: подтверждением бывает и то, чего
    /// у нас нет записью (письмо, снимок УЗИ).
    var evidence: String = ""

    var changedAt: Date = Date()
    var dog: Dog?

    init(wording: String = "", madeOn: Date = Date(),
         statusRaw: String = DiagnosisStatus.hypothesis.rawValue) {
        self.wording = wording
        self.madeOn = madeOn
        self.statusRaw = statusRaw
    }

    var status: DiagnosisStatus {
        get { DiagnosisStatus(rawValue: statusRaw) ?? .hypothesis }
        set { statusRaw = newValue.rawValue }
    }
}

nonisolated enum DiagnosisStatus: String, Codable, CaseIterable, Sendable {
    case hypothesis   // рабочая гипотеза
    case confirmed    // подтверждён
    case withdrawn    // снят

    var title: String {
        switch self {
        case .hypothesis: String(localized: "рабочая гипотеза")
        case .confirmed: String(localized: "подтверждён")
        case .withdrawn: String(localized: "снят")
        }
    }
}

/// Назначение. **Срок контроля — главное поле**, и так сказано в ТЗ:
/// это единственное место, откуда приложение может узнать, когда
/// напоминать. Сейчас эти сроки живут в текстах рецептов, и человек
/// считает их в уме.
@Model
final class Prescription {
    var id: UUID = UUID()

    /// Номер: `№ 8935331`. По нему в аптеке получают лекарство.
    var number: String = ""

    var date: Date = Date()

    var clinic: Clinic?
    var doctor: String = ""

    /// Вес собаки на дату назначения. В карте он стоит у каждого
    /// рецепта, и доза считается от него — то есть это не справка,
    /// а часть назначения.
    var dogWeightKg: Double?

    /// Что выписано.
    var medicationName: String = ""
    var dosage: String = ""
    var schedule: String = ""
    var duration: String = ""

    /// **Форма препарата — на РЕЦЕПТЕ, а не на схеме лечения.**
    /// Решение `togo-05`, и довод его решает: вопрос ретроспективный —
    /// «какая форма была в тот месяц, когда Т4 провалился». Поле
    /// на схеме отвечает «какая сейчас» и переписывает историю
    /// при смене аптеки молча. Рецепт датирован по природе.
    var pharmacyForm: String?

    /// Срок контроля в неделях, от и до. У Стича три врача назвали
    /// три разных интервала — «4–6 недель», «3 недели», «4–8 недель».
    /// Свести к одной дате значило бы придумать число за врача,
    /// поэтому окно; считает его `ControlWindow`.
    var controlFromWeeks: Int = 0
    var controlToWeeks: Int = 0

    /// Выдано: «4 таблетки».
    var dispensed: String = ""

    /// Инструкция коротко: «нанести между лопатками, не купать 24 ч
    /// до и после». Поле, а не заметка: в карте она стоит у всех
    /// тридцати пяти рецептов, то есть встречается не меньше трёх раз
    /// — порог ТЗ пройден с запасом.
    var instruction: String = ""

    /// Откуда взято: «PDF-ордоннанс», «письмо врача», «со слов».
    /// Это происхождение, и оно решает споры: в карте есть девятнадцать
    /// пробелов, где назначение известно письмом, а бланка нет вовсе —
    /// и дозу фторхинолона у пятимесячного щенка восстановить нечем.
    var source: String = ""

    var changedAt: Date = Date()
    var dog: Dog?

    init(number: String = "", date: Date = Date(), medicationName: String = "") {
        self.number = number
        self.date = date
        self.medicationName = medicationName
    }

    /// Срок контроля в том виде, в каком его понимает `ControlWindow`.
    /// Пусто — срок не назначен, и напоминать не о чем.
    var prescribedControl: ControlWindow.Prescribed? {
        guard controlFromWeeks > 0 || controlToWeeks > 0 else { return nil }
        return ControlWindow.Prescribed(fromWeeks: controlFromWeeks,
                                        toWeeks: controlToWeeks)
    }
}
