import SwiftUI
import SwiftData

// MARK: - Список анализов

/// Анализы собаки списком, и это **первая дорога к ним руками**.
///
/// **Зачем экран. Замер 08.10.2026:** четыре медицинские модели есть,
/// дорога посмотреть есть (Здоровье → «Сводка врачу»), а **ввода руками
/// нет вовсе** — `LabResult` создавался только в `MedicalRecordGallery`,
/// а она целиком под `#if DEBUG`. То есть поверхность была подключена
/// на ноль мест: модель, обмен, архив и карточки существовали, а человек
/// не мог завести ни одной записи.
///
/// > **Модель без места ввода — это не «почти готово», это ноль.**
///
/// Группа — **дата, лаборатория и номер заказа**, как в макете.
/// Бланк без номера идёт отдельной группой с явной подписью, а не
/// в группу с пустым ключом: у Togo за один день пять дефектов пришли
/// из «группировки по полю со значением по умолчанию», и в показе
/// пустота хотя бы видна человеку, а в ключе не видна никому.
struct LabResultsScreen: View {
    var dog: Dog?

    @Environment(AppState.self) private var appState
    /// Схемы лечения нужны верхнему блоку: без них не посчитать часы
    /// от дозы до забора, а они на кадре 14 стоят рядом с нормой.
    @Query private var медикаменты: [Medication]
    @State private var вводИдёт = false
    @State private var правка: LabResult?
    /// Настройки открываются из меню «…»: других кнопок в шапке нет.
    @State private var показатьНастройки = false

    /// Правит тот же, кто правит лечение: анализ — медицинская запись.
    private var canEdit: Bool { appState.can(.editTreatment) }

    private var анализы: [LabResult] {
        (dog?.labResults ?? []).sorted { $0.sampledOn > $1.sampledOn }
    }

    /// Группы бланков. Ключ — номер отчёта; пустой номер НЕ склеивается.
    private var бланки: [(ключ: String, строки: [LabResult])] {
        var порядок: [String] = []
        var карта: [String: [LabResult]] = [:]
        for анализ in анализы {
            let номер = анализ.reportNumber.trimmingCharacters(in: .whitespaces)
            // Без номера каждая строка — свой бланк: слить их по пустому
            // ключу значило бы показать разные заборы одной записью.
            let ключ = номер.isEmpty ? "без-номера-\(анализ.id.uuidString)" : номер
            if карта[ключ] == nil { порядок.append(ключ) }
            карта[ключ, default: []].append(анализ)
        }
        return порядок.map { ($0, карта[$0] ?? []) }
    }

    var body: some View {
        КиноЭкран(экран: .sub("labs"),
                  кикер: кикер.map { .готовая($0) },
                  заголовок: "Анализы",
                  настройки: { показатьНастройки = true }) {
            if анализы.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Анализов пока нет",
                    message: "Заведи бланк — лабораторию, дату и показатели. Приложение само посчитает отклонение по норме с бланка и часы от дозы.",
                    actionTitle: canEdit ? "Добавить анализ" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
                верхнийПоказатель
                TGSectionHeader(title: "анализы")
                ForEach(бланки, id: \.ключ) { бланк in
                    TGCard(spacing: 0) {
                        TGSectionHeader(title: .готовая(заголовок(бланк.строки)))
                        ForEach(Array(бланк.строки.enumerated()), id: \.element.id) { индекс, анализ in
                            if индекс > 0 { TGDivider() }
                            Button { if canEdit { правка = анализ } } label: {
                                TGListRow(
                                    title: .готовая(Fmt.notBlank(анализ.indicator) ?? String(localized: "показатель не указан")),
                                    value: .готовая(значение(анализ)),
                                    accessory: canEdit ? .chevron : .none
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit)
                        }
                    }
                }

                добавить

                TGCard {
                    TGExplainer(text: "Отклонение приложение считает само по норме с бланка. Нормы нет — так и скажет: «норма не указана», а не «в норме».")
                }
            }
        }
        .navigationDestination(isPresented: $показатьНастройки) {
            SettingsScreen()
        }
        .sheet(isPresented: $вводИдёт) { LabResultEntryFlow(dog: dog) }
        .sheet(item: $правка) { анализ in LabResultRowEditor(result: анализ) }
    }

    // MARK: Шапка и верхний блок — кадр 14

    /// Кикер: какой показатель последний и сколько всего записей.
    private var кикер: String? {
        guard let последний = последнийСЧислом else { return nil }
        let имя = Fmt.notBlank(последний.indicator) ?? String(localized: "показатель")
        return [имя, Fmt.records(анализы.count)].joined(separator: " · ")
    }

    /// Последний анализ с ЧИСЛОМ. Предел прибора (`<0,1`) сюда не входит:
    /// нарисовав его столбиком, мы превратили бы «меньше, чем прибор
    /// различает» в число.
    private var последнийСЧислом: LabResult? {
        анализы.first { $0.value != nil }
    }

    /// Блок «Metric» с кадра 14: показатель и месяц прописными, число
    /// крупно, единица и ход рядом, норма и час забора строкой,
    /// полоса ряда.
    ///
    /// **Три красные линии стреляют ровно здесь, и ни одна не согнута:**
    /// число печатает `ЧислоСБланка.показать`, а не `Fmt.decimal`
    /// (`16,75` не становится `16,8`); нормы нет на бланке — строки
    /// про норму нет вовсе, и «в норме» приложение не говорит;
    /// `labMark` — отметку лаборатории — этот блок не показывает,
    /// потому что рядом нет ни нашего вердикта, ни подписи «кто сказал».
    ///
    /// # ЛИНИИ НОРМЫ НА ПОЛОСЕ НЕТ, И ПРИЧИНА ЗАПИСАНА ЗДЕСЬ, А НЕ УМОЛЧАНА
    ///
    /// Дизайн задал её прямо (ОТВЕТЫ-круг-2, пункт 4): «линия нормы:
    /// 2 px, сплошная `text.disabled` #8E8E93. В прототипе она
    /// `text-secondary` с opacity .5, это отменено: прозрачности
    /// на линиях нет». Токены заведены — `Token.Size.metricNormLine`
    /// и `Token.Component.Metric.normLine.color`.
    ///
    /// **Читателей у них ноль** (замер 23.10.2026, контроль снят той же
    /// командой):
    ///
    /// ```
    /// metricNormLine  вне Tokens.generated.swift   0 вхождений
    /// metricBars      КОНТРОЛЬ, та же команда      1 (КиноЭкран.swift:143)
    /// ```
    ///
    /// Это класс `Token.FontSize.micro`: **опусти значение — и не
    /// покраснеет ничто**, а ступень при этом уедет дизайнеру в Фигму,
    /// и применивший получит в макете то, чего нет в приложении.
    ///
    /// ## Чего ЗДЕСЬ не хватает — и чего хватает
    ///
    /// Данных хватает, и это важнее «нет читателей»: норма у анализа
    /// есть (`referenceLow`/`referenceHigh`, уже печатается словами
    /// в `подПоказателем` — «норма 1,0–4,5»), на эталонном кадре `14`
    /// линия нарисована, и второй такой же случай — `HealthScreen`
    /// (`нормаСтрокой`). Значит это **не** «поле без предмета»:
    /// предмет есть, рисовать некому.
    ///
    /// Рисовать линию может только `КиноСтолбики` — внутри полосы,
    /// по доле от потолка ряда, — а она живёт в
    /// `Togo/Features/History/КиноЭкран.swift`, **отданном 23.10.2026
    /// другой сессии**. Параметра «норма» у неё нет, и завести его
    /// значит править чужой файл.
    ///
    /// > Поэтому решение здесь — **оставить с записанной причиной**,
    /// > и причина не «нет читателей», а «читать некому в границах
    /// > этой смены». Запись лежит рядом с предметом, а не в журнале:
    /// > уборка читает код, который сносит.
    ///
    /// **И третий вызов — не то же самое.** `HistoryScreen.ритмВыходов`
    /// зовёт `КиноМетрика` без нормы нарочно: «Это не норма, а зеркало:
    /// сравнивать стоит не с чужой собакой, а с собой месяц назад».
    /// Значит параметр обязан быть необязательным, а не выставляться
    /// у всех трёх, — и это уже требование к той правке, а не к этой.
    @ViewBuilder
    private var верхнийПоказатель: some View {
        if let последний = последнийСЧислом, let значение = последний.value {
            КиноМетрика(
                шапка: .готовая(шапкаПоказателя(последний)),
                число: ЧислоСБланка.показать(значение),
                единица: единицаСХодом(последний).map { .готовая($0) },
                пояснение: подПоказателем(последний).map { .готовая($0) },
                столбики: ряд(последний)
            )
        }
    }

    private func шапкаПоказателя(_ анализ: LabResult) -> String {
        let имя = Fmt.notBlank(анализ.indicator) ?? String(localized: "показатель")
        return [имя, анализ.sampledOn.formatted(.dateTime.month(.abbreviated))]
            .joined(separator: " · ")
    }

    /// «нмоль/л ↑ с 2,9». Стрелка и прежнее число — **только когда
    /// есть с чем сравнивать**: первая запись показателя сравнивается
    /// не с нулём, а ни с чем.
    private func единицаСХодом(_ анализ: LabResult) -> String? {
        let части = [Fmt.notBlank(анализ.unit), ход(анализ)].compactMap { $0 }
        return части.isEmpty ? nil : части.joined(separator: " ")
    }

    private func ход(_ анализ: LabResult) -> String? {
        guard let новое = анализ.value,
              let прежнее = предыдущее(анализ), прежнее != новое else { return nil }
        let было = ЧислоСБланка.показать(прежнее)
        return новое > прежнее
            ? String(localized: "↑ с \(было)")
            : String(localized: "↓ с \(было)")
    }

    private func предыдущее(_ анализ: LabResult) -> Double? {
        анализы
            .filter { $0.indicator == анализ.indicator && $0.sampledOn < анализ.sampledOn }
            .max { $0.sampledOn < $1.sampledOn }?
            .value
    }

    /// «Норма 1,0–4,5 · время забора не указано».
    ///
    /// Вторая половина — `LabSampleTiming.caption` и только он: своей
    /// формулировки у экрана быть не должно, иначе про забор напишут
    /// по-разному в трёх местах.
    ///
    /// **Часы от дозы СЧИТАЮТСЯ с 23.10.2026** — это и есть третий
    /// читатель, ради которого сводили копии.
    ///
    /// Прежняя редакция говорила: «часы здесь не считаются, и это
    /// названо; для них нужна „последняя доза до забора", а она живёт
    /// двумя копиями — `LabChartScreen.последняяДоза` и такая же
    /// в `LabResultEntryFlow`; третья копия — способ, которым правило
    /// расходится молча». Решение было верным, и платил за него
    /// **человек**: на эталонном кадре 14 верхний блок читается
    /// «Норма 1,0–4,5 · забор через 5 ч после дозы», а экран показывал
    /// одну норму.
    ///
    /// > **Отказ размножать правило — это долг показа, а не экономия.**
    /// > Пока счёт жил копиями, честный выбор был «не показывать»,
    /// > и выглядел он как аккуратность.
    ///
    /// Теперь счёт один (`DoseScheduler.sampleTiming`), а решение
    /// о точности подписи остаётся за экраном: здесь `caption`
    /// (округление до получаса, как в макете), не `captionExact`.
    ///
    /// **И «не указано» теперь говорится не всегда, когда времени нет.**
    /// Прежде строка печаталась при пустом `sampledAt` безусловно —
    /// то есть и здоровой собаке, у которой часам неоткуда взяться.
    /// `LabSampleTiming` различает это сам: `.noTreatment` подписи
    /// не даёт, и так записано в его голове с самого начала. Правило
    /// существовало, исполнять его было нечему.
    private func подПоказателем(_ анализ: LabResult) -> String? {
        var части: [String] = []
        if let низ = анализ.referenceLow, let верх = анализ.referenceHigh {
            части.append(String(localized: "норма \(ЧислоСБланка.показать(низ))–\(ЧислоСБланка.показать(верх))"))
        }
        let время = DoseScheduler.sampleTiming(sampledAt: анализ.sampledAt,
                                               of: dog, among: медикаменты)
        if let подпись = LabSampleTiming.caption(время) {
            части.append(подпись)
        }
        let живые = части.filter { !$0.isEmpty }
        return живые.isEmpty ? nil : живые.joined(separator: " · ")
    }

    private func ряд(_ анализ: LabResult) -> [Double] {
        анализы
            .filter { $0.indicator == анализ.indicator && $0.value != nil }
            .sorted { $0.sampledOn < $1.sampledOn }
            .suffix(КиноРазмеры.днейВПолосе)
            .compactMap(\.value)
    }

    /// Раздел «ДОБАВИТЬ» с кадра 14 — **он же замена кнопке «+»
    /// в шапке**, которой по дизайну больше нет.
    ///
    /// Снять «+», не переселив вход, значило бы завести у себя ровно
    /// то, что у нас называется «механизм без входа»: форма ввода
    /// существует, а дороги к ней нет.
    @ViewBuilder
    private var добавить: some View {
        if canEdit, dog != nil {
            TGSectionHeader(title: "добавить")
            Button { вводИдёт = true } label: {
                TGCard {
                    TGListRow(title: "Ввести с бланка",
                              value: "как на бланке",
                              systemImage: "square.and.pencil")
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Заголовок группы: дата · лаборатория · номер — как в макете.
    ///
    /// `Fmt.shortDay`, а не `dayTitle`: нужен «17 июл», а не
    /// «пятница · 17 июля» — день недели у бланка смысла не несёт
    /// и съедает строку, где ещё лаборатория и номер.
    private func заголовок(_ строки: [LabResult]) -> String {
        guard let первая = строки.first else { return "" }
        let номер = Fmt.notBlank(первая.reportNumber) ?? String(localized: "без номера")
        let части = [Fmt.shortDay(первая.sampledOn), Fmt.notBlank(первая.laboratory), номер]
        return части.compactMap { $0 }.joined(separator: " · ")
    }

    /// Значение строкой, и **пределы прибора остаются пределами**:
    /// `<0,1` не превращается в `0,1`. Показ идёт через
    /// `ЧислоСБланка.показать` — `Fmt.decimal` округлил бы до одного
    /// знака, и это потеря данных в медицинском числе.
    private func значение(_ анализ: LabResult) -> String {
        let единица = Fmt.notBlank(анализ.unit).map { " \($0)" } ?? ""
        if let число = анализ.value { return ЧислоСБланка.показать(число) + единица }
        if let ниже = анализ.belowLimit { return "<" + ЧислоСБланка.показать(ниже) + единица }
        if let выше = анализ.aboveLimit { return ">" + ЧислоСБланка.показать(выше) + единица }
        if let текст = Fmt.notBlank(анализ.textValue ?? "") { return текст }
        return String(localized: "значения нет")
    }
}

// MARK: - Черновик одного показателя

/// Одна строка бланка в черновике. Вид значения хранится рядом
/// со значением, а не выводится из заполненности: иначе смена вида
/// оставляла бы прежнее поле заполненным.
struct ЧерновикПоказателя: Identifiable {
    let id = UUID()
    var показатель = ""
    var вид: ВидЗначения = .равно
    var число = ""
    var текстом = ""
    var единица = ""
    var нормаНиз = ""
    var нормаВерх = ""

    var пустой: Bool {
        показатель.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Вид значения. Четыре, а не одно числовое поле.
///
/// **`<0,1 нг/дл` — это НЕ число 0,1.** `belowLimit` существует ровно
/// затем, чтобы предел прибора не стал тихо неверным числом вместо
/// видимо неизвестного, а от этого числа считают дозу. Форма с одним
/// числовым полем воспроизвела бы ровно то, от чего модель защищается.
enum ВидЗначения: String, CaseIterable, Identifiable {
    case равно, ниже, выше, текстом
    var id: String { rawValue }
    var подпись: LocalizedStringKey {
        switch self {
        case .равно: "="
        case .ниже: "<"
        case .выше: ">"
        case .текстом: "текст"
        }
    }
}

// MARK: - Ввод: три шага

/// Ввод анализа — **три шага, а не форма на двадцать полей**.
///
/// Это решение макета `8.3 · Шаг 2`, и довод у него не про красоту.
/// Первая редакция этого экрана была одной шторкой на одиннадцать полей,
/// и её отвергли по замеру: **один бланк несёт десяток показателей
/// с одной датой, лабораторией и номером**. В шторке человек вводил бы
/// десять строк и десять раз перенабирал ключ группировки — а опечатка
/// в номере на седьмой строке разорвала бы бланк на две группы, и он
/// не понял бы почему.
///
/// > **Поле, по которому группируют, нельзя заставлять набирать дважды.**
/// > Группировка — не показ, и опечатка в ней не видна глазом.
///
/// Поэтому шаг 1 спрашивает бланк один раз, шаг 2 — показатели списком,
/// шаг 3 — время забора.
///
/// ## Чего в этом вводе НЕТ, и это решения
///
/// **`labMark`** (отметка лаборатории `↑`/`↓`) — модель разрешает
/// показывать её только **вместе с нашим вердиктом и подписанными, кто
/// сказал**: «одно без другого хуже, чем ничего: расхождение станет
/// невидимым, а источник неизвестным». Поле собирается за минуту,
/// обязательство показа — нет. Завести вместе с парным показом вердикта.
///
/// **`method`** — требует правила «два значения разными методами нельзя
/// рисовать одной линией и нельзя называть расхождением». **Правила нет
/// в графике, который уже есть:** график приехал `d3fe0b0`, а `method`
/// в `LabChartScreen.swift` — ноль вхождений (замер на `527abbd`).
/// Несравнимость по ВРЕМЕНИ забора там сделана (`несравнимыеЕсть` через
/// `LabSampleTiming.comparable`), по МЕТОДУ нет ничего.
///
/// Поэтому условие на ввод — **наличие ПРАВИЛА, а не наличие графика**.
/// Прежняя редакция говорила «завести вместе с графиком»: она истекла
/// 08.10 и с того дня **разрешала неверное** — график есть, и следующий
/// законно завёл бы ввод при отсутствующем правиле.
///
/// **Что сделает эту фразу ложной — поимённо:** `method` появился
/// в `LabChartScreen.swift` (`grep -n method
/// Togo/Features/Health/LabChartScreen.swift`). До тех пор ввода нет;
/// причина и замер — в голове поля, `Medical.swift`.
///
/// > **Поле, у которого есть обязательство показа, вводить раньше показа
/// > нельзя.** Данные будут верные, а экран начнёт врать — и врать
/// > убедительно, потому что числа настоящие.
struct LabResultEntryFlow: View {
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var медикаменты: [Medication]

    @State private var шаг = 1
    // Шаг 1 — бланк, спрашивается ОДИН раз на все показатели.
    @State private var sampledOn = Date()
    @State private var лаборатория = ""
    @State private var номерБланка = ""
    @State private var раздел = ""
    // Шаг 2 — показатели.
    @State private var показатели: [ЧерновикПоказателя] = [ЧерновикПоказателя()]
    // Шаг 3 — время забора.
    @State private var времяИзвестно = false
    @State private var sampledAt = Date()
    @State private var спрашиваемПроВремя = false

    /// Какое числовое поле в фокусе. **Несёт `id` строки, а не только
    /// вид поля**, и это не перестраховка: показатели лежат
    /// в `ForEach($показатели)`, то есть три поля существуют
    /// в столько раз большем числе, сколько строк завёл человек.
    /// Перечисление из трёх случаев без `id` склеило бы «Число» первой
    /// строки с «Числом» второй, а два `.focused` с одним значением
    /// дают неопределённое поведение.
    private enum ПолеПоказателя: Hashable {
        case число(UUID), нормаНиз(UUID), нормаВерх(UUID)
    }

    @FocusState private var фокус: ПолеПоказателя?

    private var заполненные: [ЧерновикПоказателя] { показатели.filter { !$0.пустой } }

    /// Лечение идёт, если у собаки есть хоть одна непаузированная схема.
    /// От этого зависит, молча ли пропускается шаг 3.
    private var активноеЛечение: Bool {
        !DoseScheduler.activeSchedules(of: dog, among: медикаменты).isEmpty
    }

    /// Последняя доза ДО забора — **из домена, а не отсюда**.
    ///
    /// Здесь стоял свой расчёт, дословно такой же, как
    /// в `LabChartScreen`. 23.10.2026 обе копии сведены
    /// в `DoseScheduler.lastDose(before:among:)`; это свойство осталось
    /// только ради подзаголовка шага 3 («Доза была в 07:30»), которому
    /// нужен сам ЧАС, а не вывод о нём.
    ///
    /// `времяИзвестно` проверяется здесь, а не в домене: домен не знает
    /// про шаги формы, а для подписи «доза была в …» вопрос осмыслен
    /// только после того, как человек назвал время забора.
    private var последняяДоза: Date? {
        guard времяИзвестно else { return nil }
        return DoseScheduler.lastDose(
            before: sampledAt,
            among: DoseScheduler.activeSchedules(of: dog, among: медикаменты))
    }

    /// Первый вызов `LabSampleTiming` в приложении.
    ///
    /// **Замер 08.10.2026: у него не было ни одного места вызова** —
    /// чистая функция написана, покрыта смыслом и не звалась ниоткуда.
    /// Тот же класс, что сам `LabResult` без формы ввода.
    ///
    /// С 23.10.2026 вызовов три, и считает их один `DoseScheduler`.
    private var часыОтДозы: LabSampleTiming.Timing {
        DoseScheduler.sampleTiming(sampledAt: времяИзвестно ? sampledAt : nil,
                                   of: dog, among: медикаменты)
    }

    var body: some View {
        TGSheet(
            title: заголовокШага,
            subtitle: подзаголовокШага,
            closeTitle: "Отмена",
            hasUnsavedChanges: !заполненные.isEmpty || !номерБланка.isEmpty
        ) {
            TGCard {
                TGExplainer(text: .готовая(String(localized: "Шаг \(шаг) из 3")))
            }

            switch шаг {
            case 1: шагБланк
            case 2: шагПоказатели
            default: шагВремя
            }
        } footer: {
            footerШага
        }
        .presentationDetents([.large])
        // Выход с цифровой клавиатуры. Здесь полей `.decimalPad` больше
        // всех в приложении — три на каждую строку бланка, — и человек
        // набирает их подряд, то есть упирается в отсутствие выхода
        // чаще, чем где-либо.
        .готовоНадКлавиатурой { фокус = nil }
        .confirmationDialog("Сохранить без времени?",
                            isPresented: $спрашиваемПроВремя, titleVisibility: .visible) {
            Button("Сохранить так") { сохранить() }
            Button("Указать время") { времяИзвестно = true }
            Button("Отмена", role: .cancel) {}
        } message: {
            // Алерт НАЗЫВАЕТ ПОСЛЕДСТВИЕ, а не просит подтверждения, —
            // в этом и разница между трением и вопросом. Текст из макета.
            Text("Анализ будет помечен «время не указано» и на графике встанет пустым кружком.")
        }
    }

    // MARK: Шаги

    private var заголовокШага: LocalizedStringKey {
        switch шаг {
        case 1: "Когда и где"
        case 2: "Показатели"
        default: "Забор во сколько?"
        }
    }

    private var подзаголовокШага: LocalizedStringKey? {
        switch шаг {
        case 1: "бланк спрашиваем один раз — он общий для всех строк"
        case 2: "сколько строк на бланке, столько и добавь"
        default:
            if let доза = последняяДоза {
                .готовая(String(localized: "Доза была в \(Fmt.clock(доза))."))
            } else {
                "по нему видно, сколько прошло от таблетки до забора"
            }
        }
    }

    private var шагБланк: some View {
        TGCard(spacing: 0) {
            LabeledField(label: "Лаборатория") {
                // Был «IDEXX» — название ПОСТАВЩИКА услуги, работающего
                // не во всякой стране. Это тот же класс, что `+33…`
                // у телефона: догадка о том, где человек живёт,
                // и реклама одной лаборатории заодно.
                //
                // И пример был уже, чем поле: `Medical.swift:41` говорит
                // «Лаборатория: IDEXX · Antech · КЛИНИКА» — анализ часто
                // сдают в обычной клинике, а подсказка-бренд читалась
                // как «сюда пишут только лаборатории».
                //
                // Действующее вещество (`Левотироксин`) при этом
                // оставлено: у МНН есть официальная форма в каждом
                // языке, и перевод его — работа, а не шум. Поставщик
                // такой формы не имеет по устройству.
                TextField("где сдавали", text: $лаборатория)
            }
            TGDivider()
            LabeledField(label: "Номер бланка") {
                // Был номер живого бланка лаборатории. «как на бланке»
                // говорит то же, что говорил пример — переписывай
                // посимвольно, буквы тоже, — и не выносит наружу номер
                // чужого документа. Ключ уже есть в каталоге (:286),
                // переводы у него тоже.
                TextField("как на бланке", text: $номерБланка)
            }
            TGDivider()
            LabeledField(label: "Раздел") {
                TextField("гормоны", text: $раздел)
            }
            TGDivider()
            DatePicker("Дата забора", selection: $sampledOn, displayedComponents: .date)
                .frame(minHeight: Token.Size.tapTarget)
            TGExplainer(text: "Номер связывает строки одного бланка между собой — в списке они встанут вместе.")
        }
    }

    @ViewBuilder
    private var шагПоказатели: some View {
        ForEach($показатели) { $строка in
            TGCard(spacing: 0) {
                LabeledField(label: "Показатель") {
                    TextField("Т4 общий", text: $строка.показатель)
                }
                TGDivider()
                Picker("Вид значения", selection: $строка.вид) {
                    ForEach(ВидЗначения.allCases) { Text($0.подпись).tag($0) }
                }
                .pickerStyle(.segmented)

                if строка.вид == .текстом {
                    TextField("выделен штамм стафилококка", text: $строка.текстом, axis: .vertical)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                } else {
                    LabeledField(label: "Число") {
                        TextField("с бланка", text: $строка.число).keyboardType(.decimalPad)
                            .focused($фокус, equals: .число(строка.id))
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Единица") {
                        TextField("нг/дл", text: $строка.единица)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    TGDivider()
                    LabeledField(label: "Норма от") {
                        TextField("с бланка", text: $строка.нормаНиз).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаНиз(строка.id))
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Норма до") {
                        TextField("с бланка", text: $строка.нормаВерх).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаВерх(строка.id))
                            .autocorrectionDisabled()
                    }
                }

                if строка.вид == .ниже || строка.вид == .выше {
                    TGExplainer(text: "Это предел прибора, а не результат. Приложение сохранит его пределом и не выдаст за измеренное число.")
                }

                if показатели.count > 1 {
                    TGButton(title: "Убрать строку", variant: .destructive, size: .medium, systemImage: "minus.circle") {
                        показатели.removeAll { $0.id == строка.id }
                    }
                }
            }
        }

        TGButton(title: "Ещё показатель", variant: .secondary, size: .medium, systemImage: "plus") {
            показатели.append(ЧерновикПоказателя())
        }

        TGCard {
            TGExplainer(text: "Норму приложение не подставляет: нет на бланке — скажет «норма не указана». Отклонение считается, а не вводится.")
        }

        // Запас внизу шага 2, и он не косметический. Кадр 08.10.2026,
        // снятый не автором: при ПОДНЯТОЙ КЛАВИАТУРЕ «Норма от» видно
        // наполовину, «Норма до» не видно вовсе — поля уходят под
        // закреплённую кнопку «Дальше».
        //
        // > **Экран, который влез без клавиатуры, не влез с клавиатурой.**
        // > Проверка на узком экране и на крупном шрифте этого не ловит:
        // > высоту съедает не шрифт, а то, что появляется от касания
        // > по полю, то есть ТОЛЬКО во время ввода.
        //
        // Запас высотой в цель касания: меньше не даёт докрутить
        // последнее поле, больше оставляет пустоту на экране без
        // клавиатуры.
        Spacer(minLength: Token.Size.tapTarget * 2)
    }

    private var шагВремя: some View {
        TGCard {
            Toggle(isOn: $времяИзвестно) {
                Text("Время забора известно").textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)

            if времяИзвестно {
                DatePicker("Время забора", selection: $sampledAt, displayedComponents: .hourAndMinute)
                    .frame(minHeight: Token.Size.tapTarget)
            }

            // Часы считаются НА ГЛАЗАХ — макет требует этого прямо:
            // «без них результат не сравнить с другими».
            if let подпись = LabSampleTiming.captionExact(часыОтДозы) {
                TGDivider()
                Text(verbatim: подпись)
                    .textStyle(AppFont.body)
            }

            TGExplainer(text: времяИзвестно
                        ? "Часы от дозы приложение считает само — вводить их не нужно."
                        : "Без времени так и запишем — «время не указано». Это честнее, чем угадать: подставь мы «вероятно, утром», запись сказала бы врачу то, чего ты не вводил.")
        }
    }

    // MARK: Низ

    @ViewBuilder
    private var footerШага: some View {
        switch шаг {
        case 1:
            TGButton(title: "Дальше", isEnabled: true) { шаг = 2 }
        case 2:
            TGButton(title: "Дальше", isEnabled: !заполненные.isEmpty) { шаг = 3 }
        default:
            TGButton(title: "Сохранить анализ", systemImage: "checkmark") { сохранитьПроверив() }
        }
    }

    /// **При активном лечении шаг не пропускается молча.**
    ///
    /// Требование модели: время забора «обязательно при активном лечении»,
    /// и это слово врача, а не удобство — без него результат
    /// не интерпретируется. Первая редакция этого экрана оставляла
    /// тумблер и сохраняла беззвучно: поле я не подставил, а **трение
    /// потерял**, то есть сделал тихо ровно то, от чего модель
    /// защищается словами «молча не пропускается».
    private func сохранитьПроверив() {
        if !времяИзвестно, активноеЛечение {
            спрашиваемПроВремя = true
            return
        }
        сохранить()
    }

    /// Одна запись на показатель; бланк у всех общий.
    private func сохранить() {
        guard let dog else { dismiss(); return }
        let строки = заполненные
        guard !строки.isEmpty else { dismiss(); return }

        var созданные: [LabResult] = []
        for черновик in строки {
            let анализ = LabResult(sampledOn: sampledOn,
                                   indicator: черновик.показатель.trimmingCharacters(in: .whitespaces),
                                   section: раздел.trimmingCharacters(in: .whitespaces),
                                   laboratory: лаборатория.trimmingCharacters(in: .whitespaces),
                                   reportNumber: номерБланка.trimmingCharacters(in: .whitespaces))
            анализ.sampledAt = времяИзвестно ? sampledAt : nil
            анализ.unit = черновик.единица.trimmingCharacters(in: .whitespaces)
            анализ.referenceLow = ЧислоСБланка.разобрать(черновик.нормаНиз)
            анализ.referenceHigh = ЧислоСБланка.разобрать(черновик.нормаВерх)

            // Все четыре поля значения выставляются РАЗОМ, три из них
            // в `nil`: `measuredValue` читает их по очереди и берёт
            // первое непустое, поэтому остаток прежнего вида соврал бы.
            let число = ЧислоСБланка.разобрать(черновик.число)
            анализ.value = черновик.вид == .равно ? число : nil
            анализ.belowLimit = черновик.вид == .ниже ? число : nil
            анализ.aboveLimit = черновик.вид == .выше ? число : nil
            let текст = черновик.текстом.trimmingCharacters(in: .whitespaces)
            анализ.textValue = черновик.вид == .текстом && !текст.isEmpty ? текст : nil

            анализ.changedAt = Date()
            анализ.dog = dog
            context.insert(анализ)
            созданные.append(анализ)
        }

        // Откат всей партии, если хранилище не приняло: экран, закрывшийся
        // с «получилось» после несохранённого бланка, обещает врачу
        // записи, которых нет.
        guard context.persist(otherwise: {
            for анализ in созданные {
                анализ.dog = nil
                context.delete(анализ)
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Сохранить анализ» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Правка одной строки

/// Правка ОДНОЙ существующей строки — здесь шторка верна.
///
/// Трёхшаговый ход заведён против перенабора общего бланка; у одной
/// строки общего бланка нет, и разбивать её правку на шаги значило бы
/// перенести ход туда, где его довод не действует.
struct LabResultRowEditor: View {
    let result: LabResult

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var черновик = ЧерновикПоказателя()
    @State private var загружено = false
    @State private var удаляем = false

    /// Какое числовое поле в фокусе. Здесь **без** `id`, в отличие
    /// от `LabResultEntryFlow`: черновик один на весь лист, цикла нет,
    /// и три случая различают поля однозначно. Форма условия названа
    /// по тому, что есть, а не скопирована у соседа.
    private enum ПолеСтроки: Hashable { case число, нормаНиз, нормаВерх }

    @FocusState private var фокус: ПолеСтроки?

    var body: some View {
        TGSheet(title: .готовая(Fmt.notBlank(result.indicator) ?? String(localized: "Анализ")),
                subtitle: "строка бланка",
                closeTitle: "Закрыть") {
            TGCard(spacing: 0) {
                LabeledField(label: "Показатель") {
                    TextField("Т4 общий", text: $черновик.показатель)
                }
                TGDivider()
                Picker("Вид значения", selection: $черновик.вид) {
                    ForEach(ВидЗначения.allCases) { Text($0.подпись).tag($0) }
                }
                .pickerStyle(.segmented)

                if черновик.вид == .текстом {
                    TextField("результат словами", text: $черновик.текстом, axis: .vertical)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                } else {
                    TGDivider()
                    LabeledField(label: "Число") {
                        TextField("с бланка", text: $черновик.число).keyboardType(.decimalPad)
                            .focused($фокус, equals: .число)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Единица") {
                        TextField("нг/дл", text: $черновик.единица)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    TGDivider()
                    LabeledField(label: "Норма от") {
                        TextField("с бланка", text: $черновик.нормаНиз).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаНиз)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Норма до") {
                        TextField("с бланка", text: $черновик.нормаВерх).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаВерх)
                            .autocorrectionDisabled()
                    }
                }
            }

            TGButton(title: "Удалить строку", variant: .destructive, size: .medium, systemImage: "trash") {
                удаляем = true
            }
        } footer: {
            TGButton(title: "Сохранить", isEnabled: !черновик.пустой) { сохранить() }
        }
        .presentationDetents([.large])
        // Выход с цифровой клавиатуры.
        .готовоНадКлавиатурой { фокус = nil }
        .task { загрузить() }
        .confirmationDialog("Удалить строку?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                context.delete(result)
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Строка уйдёт из списка и из отчёта врачу. Остальные строки этого бланка останутся.")
        }
    }

    private func загрузить() {
        guard !загружено else { return }
        черновик.показатель = result.indicator
        черновик.единица = result.unit
        черновик.нормаНиз = ЧислоСБланка.текст(result.referenceLow)
        черновик.нормаВерх = ЧислоСБланка.текст(result.referenceHigh)
        // Вид выводится из того, какое поле заполнено: две копии одного
        // решения разошлись бы молча.
        if let число = result.value {
            черновик.вид = .равно
            черновик.число = ЧислоСБланка.текст(число)
        } else if let ниже = result.belowLimit {
            черновик.вид = .ниже
            черновик.число = ЧислоСБланка.текст(ниже)
        } else if let выше = result.aboveLimit {
            черновик.вид = .выше
            черновик.число = ЧислоСБланка.текст(выше)
        } else if let текст = Fmt.notBlank(result.textValue ?? "") {
            черновик.вид = .текстом
            черновик.текстом = текст
        }
        загружено = true
    }

    private func сохранить() {
        let былПоказатель = result.indicator
        let былаЕдиница = result.unit
        let былоЗначение = result.value
        let былНиже = result.belowLimit
        let былВыше = result.aboveLimit
        let былТекст = result.textValue
        let былаНормаНиз = result.referenceLow
        let былаНормаВерх = result.referenceHigh
        let былоИзменено = result.changedAt

        result.indicator = черновик.показатель.trimmingCharacters(in: .whitespaces)
        result.unit = черновик.единица.trimmingCharacters(in: .whitespaces)
        result.referenceLow = ЧислоСБланка.разобрать(черновик.нормаНиз)
        result.referenceHigh = ЧислоСБланка.разобрать(черновик.нормаВерх)

        let число = ЧислоСБланка.разобрать(черновик.число)
        result.value = черновик.вид == .равно ? число : nil
        result.belowLimit = черновик.вид == .ниже ? число : nil
        result.aboveLimit = черновик.вид == .выше ? число : nil
        let текст = черновик.текстом.trimmingCharacters(in: .whitespaces)
        result.textValue = черновик.вид == .текстом && !текст.isEmpty ? текст : nil

        // Время правки на ЭТОМ телефоне — им решается спор двух телефонов
        // при обмене.
        result.changedAt = Date()

        guard context.persist(otherwise: {
            result.indicator = былПоказатель
            result.unit = былаЕдиница
            result.value = былоЗначение
            result.belowLimit = былНиже
            result.aboveLimit = былВыше
            result.textValue = былТекст
            result.referenceLow = былаНормаНиз
            result.referenceHigh = былаНормаВерх
            result.changedAt = былоИзменено
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Сохранить» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
