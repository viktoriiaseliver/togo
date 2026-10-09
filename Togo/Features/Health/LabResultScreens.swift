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
    @State private var вводИдёт = false
    @State private var правка: LabResult?

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
        TGScreen {
            if анализы.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Анализов пока нет",
                    message: "Заведи бланк — лабораторию, дату и показатели. Приложение само посчитает отклонение по норме с бланка и часы от дозы.",
                    actionTitle: canEdit ? "Добавить анализ" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
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

                TGCard {
                    TGExplainer(text: "Отклонение приложение считает само по норме с бланка. Нормы нет — так и скажет: «норма не указана», а не «в норме».")
                }
            }
        }
        .navigationTitle("Анализы")
        .posterHeader("Анализы")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canEdit, dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { вводИдёт = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить анализ")
                }
            }
        }
        .sheet(isPresented: $вводИдёт) { LabResultEntryFlow(dog: dog) }
        .sheet(item: $правка) { анализ in LabResultRowEditor(result: анализ) }
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

    private var заполненные: [ЧерновикПоказателя] { показатели.filter { !$0.пустой } }

    /// Лечение идёт, если у собаки есть хоть одна непаузированная схема.
    /// От этого зависит, молча ли пропускается шаг 3.
    private var активноеЛечение: Bool {
        guard let dog else { return false }
        return медикаменты.contains {
            $0.dog?.persistentModelID == dog.persistentModelID && !$0.isPaused
        }
    }

    /// Последняя доза ДО забора — из часов схемы на день забора.
    /// Чистая арифметика по расписанию: журнала приёмов здесь не спрашиваем,
    /// потому что бланк могли вводить задним числом.
    private var последняяДоза: Date? {
        guard let dog, времяИзвестно else { return nil }
        let свои = медикаменты.filter {
            $0.dog?.persistentModelID == dog.persistentModelID && !$0.isPaused
        }
        let начало = Calendar.current.startOfDay(for: sampledAt)
        let времена = свои.flatMap(\.times).compactMap {
            Calendar.current.date(byAdding: .minute, value: $0, to: начало)
        }
        return времена.filter { $0 <= sampledAt }.max()
    }

    /// Первый вызов `LabSampleTiming` в приложении.
    ///
    /// **Замер 08.10.2026: у него не было ни одного места вызова** —
    /// чистая функция написана, покрыта смыслом и не звалась ниоткуда.
    /// Тот же класс, что сам `LabResult` без формы ввода.
    private var часыОтДозы: LabSampleTiming.Timing {
        LabSampleTiming.timing(sampledAt: времяИзвестно ? sampledAt : nil,
                               lastDoseAt: последняяДоза,
                               hasActiveTreatment: активноеЛечение)
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
                TextField("IDEXX", text: $лаборатория)
            }
            TGDivider()
            LabeledField(label: "Номер бланка") {
                TextField("VF120682", text: $номерБланка)
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
                        TextField("12,9", text: $строка.число).keyboardType(.decimalPad)
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
                        TextField("12,9", text: $строка.нормаНиз).keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Норма до") {
                        TextField("51,5", text: $строка.нормаВерх).keyboardType(.decimalPad)
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
                        TextField("12,9", text: $черновик.число).keyboardType(.decimalPad)
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
                        TextField("12,9", text: $черновик.нормаНиз).keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Норма до") {
                        TextField("51,5", text: $черновик.нормаВерх).keyboardType(.decimalPad)
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
