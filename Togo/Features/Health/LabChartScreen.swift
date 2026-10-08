import SwiftUI
import SwiftData
import Charts

/// График показателя во времени — то, ради чего медслой затевался.
///
/// **Вопрос, на который он отвечает:** «почему Т4 не растёт при росте
/// дозы». В карте Стича доза выросла в пять раз, а Т4 упал до 6,0 —
/// и увидеть это можно только рядом, во времени.
///
/// ## Первая часть из двух, и она самодостаточна
///
/// Здесь: линия показателя, полоса нормы фоном, **форма маркера
/// по времени забора**, отклонение словом в таблице, период
/// и «Сравнивать пока не с чем» на одной точке.
///
/// Второй частью идут **столбики дозы** у каждой точки и карточка
/// по тапу (четыре величины словами). Их нет не потому, что забыли:
/// доза на дату — отдельный расчёт по расписанию схемы, и её лучше
/// заводить вместе с карточкой точки, где она и названа словом.
///
/// Разделено так нарочно: половина графика, которая **собирается
/// и показывает полосу нормы**, — это работа. Половина в дереве —
/// брошенное.
///
/// ## Три правила, которые здесь исполняются, а не упоминаются
///
/// **1. Отклонение — словом, а не только цветом и положением.**
/// Слово берётся у `LabNorm.word`, а не пишется здесь: иначе вторая
/// поверхность напишет своё, и у Togo это уже было — виджет считал
/// окно «не кормить» собственной арифметикой.
///
/// **2. Разное время забора — не расхождение.** `LabSampleTiming`
/// держит порог в три часа, и он взят из карты: 3,5 ч против 11,5 ч
/// при одной дозе дали **противоположные выводы**. Поэтому форма
/// маркера различает время забора, а несравнимые точки прямо названы
/// в таблице.
///
/// **3. Подпись часов — ОКРУГЛЁННАЯ (`caption`), не точная.**
/// Две функции лежат в одном файле, и завёл их я же: на вводе нужна
/// точность до минуты, на графике — получас, как в дизайне («+3,5 ч»,
/// «+11,5 ч»).
///
/// > Я помню про себя «я сделал точную» — и именно поэтому адрес
/// > назван буквой: здесь `caption`. Память о своём решении сильнее
/// > кода, и особенно у автора.
///
/// Цвета: показатель — акцент, норма — нейтраль. **Янтарь и терракот
/// не используются: они заняты** состояниями дозы и просрочки.
struct LabChartScreen: View {
    var dog: Dog?

    @Environment(AppState.self) private var appState
    @Query private var медикаменты: [Medication]

    @State private var показатель: String?
    @State private var период: Период = .всё

    enum Период: String, CaseIterable, Identifiable {
        case полгода = "6 мес", год = "год", всё = "всё"
        var id: String { rawValue }
        var месяцев: Int? {
            switch self {
            case .полгода: 6
            case .год: 12
            case .всё: nil
            }
        }
    }

    /// Одна точка графика. Собирается здесь, а не во вью: вью не должен
    /// знать, как считается время от дозы.
    struct Точка: Identifiable {
        let id: UUID
        let дата: Date
        let значение: Double
        let единица: String
        let вердикт: LabNorm.Deviation
        let время: LabSampleTiming.Timing
        let норма: LabNorm.Reference
    }

    private var всеАнализы: [LabResult] { dog?.labResults ?? [] }

    /// Показатели, у которых есть хотя бы одно ЧИСЛО. Текстовые
    /// результаты (бактериология) в график не идут — им нечего рисовать,
    /// и это не пропуск, а природа величины.
    private var доступныеПоказатели: [String] {
        var видели = Set<String>()
        var порядок: [String] = []
        for анализ in всеАнализы.sorted(by: { $0.sampledOn > $1.sampledOn }) {
            guard анализ.value != nil else { continue }
            let имя = анализ.indicator.trimmingCharacters(in: .whitespaces)
            guard !имя.isEmpty, !видели.contains(имя) else { continue }
            видели.insert(имя)
            порядок.append(имя)
        }
        return порядок
    }

    private var выбранный: String? { показатель ?? доступныеПоказатели.first }

    private var активноеЛечение: Bool {
        guard let dog else { return false }
        return медикаменты.contains {
            $0.dog?.persistentModelID == dog.persistentModelID && !$0.isPaused
        }
    }

    /// Последняя доза ДО забора — арифметикой по расписанию схемы
    /// на день забора. Журнал приёмов не спрашиваем: бланк могли
    /// вводить задним числом.
    private func последняяДоза(до момент: Date) -> Date? {
        guard let dog else { return nil }
        let свои = медикаменты.filter {
            $0.dog?.persistentModelID == dog.persistentModelID && !$0.isPaused
        }
        let начало = Calendar.current.startOfDay(for: момент)
        let времена = свои.flatMap(\.times).compactMap {
            Calendar.current.date(byAdding: .minute, value: $0, to: начало)
        }
        return времена.filter { $0 <= момент }.max()
    }

    private var точки: [Точка] {
        guard let выбранный else { return [] }
        let порог: Date? = период.месяцев.flatMap {
            Calendar.current.date(byAdding: .month, value: -$0, to: Date())
        }
        return всеАнализы
            .filter { $0.indicator.trimmingCharacters(in: .whitespaces) == выбранный }
            .filter { порог == nil || $0.sampledOn >= порог! }
            .compactMap { анализ -> Точка? in
                guard let значение = анализ.value else { return nil }
                let время = LabSampleTiming.timing(
                    sampledAt: анализ.sampledAt,
                    lastDoseAt: анализ.sampledAt.flatMap { последняяДоза(до: $0) },
                    hasActiveTreatment: активноеЛечение)
                return Точка(
                    id: анализ.id,
                    дата: анализ.sampledOn,
                    значение: значение,
                    единица: анализ.unit,
                    вердикт: LabNorm.deviation(value: .measured(значение), from: анализ.reference),
                    время: время,
                    норма: анализ.reference)
            }
            .sorted { $0.дата < $1.дата }
    }

    /// Полоса нормы: берётся у последней точки, у которой норма есть.
    /// Если нормы нет ни у одной — полосы нет, **и это не повод
    /// не рисовать точки**: так записано у `bandBounds`.
    /// Ярлыки кортежа взяты у `bandBounds` (`low`/`high`), а не свои:
    /// компилятор не приводит `(low:high:)` к `(низ:верх:)`, и переводить
    /// их здесь значило бы заводить второе имя одной величины.
    private var полоса: (low: Double?, high: Double?)? {
        for точка in точки.reversed() {
            if let границы = LabNorm.bandBounds(точка.норма) { return границы }
        }
        return nil
    }

    var body: some View {
        TGScreen {
            if доступныеПоказатели.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Рисовать пока нечего",
                    message: "График появится, когда будет хотя бы один анализ с числом. Бактериология и описания в график не идут — им нечего рисовать."
                )
            } else {
                выборПоказателя
                if точки.count < 2 { нечегоСравнивать } else { график }
                таблица
            }
        }
        .navigationTitle("График")
        .posterHeader("График")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Выбор

    private var выборПоказателя: some View {
        TGCard {
            if доступныеПоказатели.count > 1 {
                Picker("Показатель", selection: Binding(
                    get: { выбранный ?? "" },
                    set: { показатель = $0 }
                )) {
                    ForEach(доступныеПоказатели, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
            }
            Picker("Период", selection: $период) {
                ForEach(Период.allCases) { Text(verbatim: $0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// **Одна точка — не график.** Так и сказано словами, а не пустой
    /// областью: пустая область читается как «не загрузилось».
    private var нечегоСравнивать: some View {
        TGCard {
            TGSectionHeader(title: .готовая(выбранный ?? ""))
            Text("Сравнивать пока не с чем")
                .textStyle(AppFont.body)
            TGExplainer(text: точки.isEmpty
                        ? "За выбранный период анализов с числом нет. Поменяй период — или заведи анализ."
                        : "Есть одна точка. График начнёт говорить со второй: он про то, как величина меняется, а не какая она сейчас.")
        }
    }

    // MARK: График

    private var график: some View {
        TGCard {
            TGSectionHeader(title: .готовая(заголовокГрафика))
            Chart {
                // Полоса нормы — ФОНОМ и нейтралью. Рисуется первой,
                // чтобы линия шла поверх неё.
                if let полоса, let низ = полоса.low, let верх = полоса.high {
                    RectangleMark(
                        yStart: .value("низ нормы", низ),
                        yEnd: .value("верх нормы", верх)
                    )
                    .foregroundStyle(Token.Ink.silhouette.opacity(0.18))
                }

                ForEach(точки) { точка in
                    LineMark(
                        x: .value("дата", точка.дата),
                        y: .value("значение", точка.значение)
                    )
                    .foregroundStyle(Token.Action.primary)

                    PointMark(
                        x: .value("дата", точка.дата),
                        y: .value("значение", точка.значение)
                    )
                    .foregroundStyle(Token.Action.primary)
                    // **Форма маркера — время забора.** Требование
                    // дизайна и ТЗ: точки с разным временем забора
                    // обязаны быть различимы НА ВИД, иначе человек
                    // сравнит несравнимое — в карте это случилось дважды.
                    .symbol(символ(точка.время))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
            // Доступность: сам график для VoiceOver — одна фигура,
            // поэтому ниже лежит таблица, и она не дубль, а вторая
            // поверхность той же правды.
            .accessibilityHidden(true)

            легенда
        }
    }

    private var заголовокГрафика: String {
        let единица = точки.compactMap { Fmt.notBlank($0.единица) }.last
        let имя = выбранный ?? ""
        return единица.map { "\(имя), \($0)" } ?? имя
    }

    /// Пустой кружок — «время забора не указано», и это ОТВЕТ,
    /// а не пропуск: `LabSampleTiming` держит этот случай отдельным
    /// видом ровно затем, чтобы он был виден на графике.
    private func символ(_ время: LabSampleTiming.Timing) -> BasicChartSymbolShape {
        switch время {
        case .hoursSinceDose: .circle
        case .noTreatment: .square
        case .unknownDuringTreatment: .cross
        }
    }

    private var легенда: some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text("Полоса — норма с бланка. Форма точки — время забора: круг — часы от дозы известны, крест — не записаны, квадрат — лечения в тот день не было.")
                .textStyle(AppFont.caption.color(Token.Ink.secondary))
                .wraps()
        }
    }

    // MARK: Таблица — она же доступность

    /// Таблица, а не подпись у точки.
    ///
    /// **Это не дубль графика, а требование доступности:** на крупных
    /// размерах шрифта и для VoiceOver график не читается вовсе,
    /// и дизайн прямо требует таблицу вместо него. Каждая строка
    /// читается целиком: дата, значение, отклонение СЛОВОМ, часы.
    private var таблица: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "по датам")
            ForEach(Array(точки.reversed().enumerated()), id: \.element.id) { индекс, точка in
                if индекс > 0 { TGDivider() }
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: Fmt.shortDay(точка.дата))
                            .textStyle(AppFont.body)
                        Spacer(minLength: Token.Space.s8)
                        Text(verbatim: ЧислоСБланка.показать(точка.значение)
                             + (Fmt.notBlank(точка.единица).map { " \($0)" } ?? ""))
                            .textStyle(AppFont.numeric(15))
                    }
                    // Отклонение СЛОВОМ, из LabNorm — не своё.
                    Text(verbatim: LabNorm.word(точка.вердикт))
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    // Часы ОКРУГЛЁННО: `caption`, не `captionExact`.
                    // `если(_:)` из MedicalRecordCards здесь недоступен —
                    // он приватный, и копировать его ради одной строки
                    // значило бы завести второго хозяина у помощника.
                    if let подпись = LabSampleTiming.caption(точка.время) {
                        Text(verbatim: подпись)
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                .accessibilityElement(children: .combine)
            }

            if несравнимыеЕсть {
                TGExplainer(text: "Точки сняты в разное время после дозы — такие значения рядом не сравнивают без оговорки. Время забора у каждой строки выше.")
            }
        }
    }

    /// Есть ли в наборе пара, которую сравнивать нельзя.
    /// Спрашивается у `LabSampleTiming.comparable`, а не считается здесь:
    /// порог три часа — его решение, и второй копии у него быть не должно.
    private var несравнимыеЕсть: Bool {
        let времена = точки.map(\.время)
        for левый in времена.indices {
            for правый in времена.indices where правый > левый {
                if !LabSampleTiming.comparable(времена[левый], времена[правый]) { return true }
            }
        }
        return false
    }
}
