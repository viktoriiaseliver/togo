import SwiftUI
import SwiftData

// MARK: - Список назначений

/// Назначения списком и ввод руками.
///
/// **Эта форма — последнее недостающее звено уже работающего механизма,
/// и это главное, что про неё надо знать.** Замер 08.10.2026:
///
/// ```
/// ReminderScheduler:131   ControlWindow.window(prescribedAt: рецепт.date, …)
/// ControlWindow           окно, ступени, даты напоминаний — всё есть
/// рецептов, которые может завести человек   НОЛЬ
/// ```
///
/// То есть напоминания про контроль были написаны, разобраны по ступеням
/// («рано», «окно открыто», «последний день», «пропущено») и **никогда
/// ни о чём не напоминали**: единственное место, где создавался
/// `Prescription`, — отладочная галерея под `#if DEBUG`.
///
/// > **Механизм без входа не «почти работает» — он не работает.**
/// > И отличить это от «работает» нельзя ни тестом, ни компилятором:
/// > тесты заводят рецепты сами.
///
/// Новое сверху, номер первым в строке — решение макета `8.2`:
/// по номеру получают лекарство в аптеке, и в списке ищут именно его.
struct PrescriptionsScreen: View {
    var dog: Dog?

    @Environment(AppState.self) private var appState
    @State private var вводИдёт = false
    @State private var правка: Prescription?

    private var canEdit: Bool { appState.can(.editTreatment) }

    private var назначения: [Prescription] {
        (dog?.prescriptions ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Назначения", надпись: "для аптеки", отступы: false)
            // Плашка — ДО первого отказа: строки рецептов выключены `.disabled(!canEdit)` (`:65`),
            // а `.disabled` молчит по устройству. Правило дизайна
            // круга 5, п. 1; разбор и причина одного типа на все
            // экраны — `ПлашкаПрава`.
            if !canEdit { ПлашкаПрава(право: .editTreatment) }
            if назначения.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Назначений пока нет",
                    message: "Заведи рецепт — номер, что выписано и срок контроля. По сроку приложение напомнит: в начале окна и в последний день.",
                    actionTitle: canEdit ? "Добавить назначение" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
                TGCard(spacing: 0) {
                    ForEach(Array(назначения.enumerated()), id: \.element.id) { индекс, рецепт in
                        if индекс > 0 { TGDivider() }
                        Button { if canEdit { правка = рецепт } } label: {
                            TGListRow(
                                title: .готовая(строка(рецепт)),
                                value: .готовая(Fmt.shortDay(рецепт.date)),
                                systemImage: "doc.text",
                                accessory: canEdit ? .chevron : .none
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                }

                TGCard {
                    TGExplainer(text: "Срок контроля — диапазоном, а не датой: три врача называют три разных интервала, и выбирать за них приложение не будет. Напомним в начале окна и в последний день.")
                }
            }
        }
        .navigationTitle("Назначения")
        .cinemaScreen(экран: .sub("rx"))
        .toolbar {
            if canEdit, dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { вводИдёт = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить назначение")
                }
            }
        }
        .sheet(isPresented: $вводИдёт) { PrescriptionEditor(dog: dog) }
        .sheet(item: $правка) { рецепт in PrescriptionEditor(prescription: рецепт, dog: dog) }
    }

    /// Номер первым: по нему получают лекарство, и по нему ищут.
    private func строка(_ рецепт: Prescription) -> String {
        let номер = Fmt.notBlank(рецепт.number).map { "№ \($0)" }
        let что = Fmt.notBlank(рецепт.medicationName)
        let части = [номер, что]
        let собрано = части.compactMap { $0 }.joined(separator: " · ")
        return собрано.isEmpty ? String(localized: "рецепт без номера") : собрано
    }
}

// MARK: - Форма

/// Ввод назначения. Одна шторка: у рецепта одна запись на форму,
/// общего ключа группировки нет — трёхшаговый ход анализа здесь
/// не нужен, и макет `8.2` рисует её именно формой.
///
/// ## «Показать в аптеке» — ДОЛГ ЗАКРЫТ 08.10.2026
///
/// Здесь стояло «чего в форме НЕТ», и условие было записано так:
/// «отдельная поверхность, и у неё есть обязательство, которого
/// в одну строку не выполнить — **яркость надо вернуть**; заводить
/// вместе с кадром и восстановлением яркости на уходе с экрана».
///
/// Условие исполнено, а не описано: `PharmacyNumberScreen` ниже,
/// кнопка в редакторе, яркость — `.яркостьНаМаксимум()`. Возврат там
/// висит на ДВУХ механизмах, которые вместе закрывают четыре дороги
/// ухода: `onDisappear` (кнопка и свайп) и `scenePhase` (сворачивание
/// и блокировка). Запись оставлена зачёркнутой, а не
/// удалённой: удалённая не предупреждает о себе, и следующий прочёл бы
/// пустоту так же, как читают «не сделано».
///
/// > **Голова модуля, называющая долг, обязана перестать называть его
/// > в том же коммите, где долг закрыт.** Иначе она описывает
/// > отменённое состояние — а это читают ВМЕСТО кода.
///
/// ## Чего в форме НЕТ, и это названный долг с условием
///
/// **Напоминания тумблером.** `ReminderScheduler` уже читает рецепты
/// и считает даты по `ControlWindow` — значит напоминания появятся
/// от самого факта заведённого срока. Отдельный тумблер «напомнить»
/// здесь был бы вторым хозяином у одного решения; включать его
/// надо там, где живут остальные разрешения на уведомления.
struct PrescriptionEditor: View {
    var prescription: Prescription?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var всеКлиники: [Clinic]

    /// Кто назначил — **клиники, БЕЗ лабораторий**. Требование модели
    /// (`Clinic.swift:34`): «туда сдают анализы, там не принимают»,
    /// а рецепт выписывает принимающий врач. До 26.10.2026 фильтра
    /// не было, и в списке «кто назначил» стояли IDEXX и Antech.
    ///
    /// **Выбранная остаётся в списке всегда** — иначе правка старого
    /// рецепта молча теряла бы организацию: пикер показал бы
    /// «не указана» при заполненном `prescription.clinic`, а
    /// `цель.clinic = клиника` записало бы `nil`. Фильтр показа стал бы
    /// молчаливым удалением данных. Разбор — у двойника
    /// в `VetVisitEditor`.
    private var доступные: [Clinic] {
        let живые = всеКлиники.filter { $0.deletedAt == nil && !$0.isLab }
        let выбранная = клиника.map { [$0] } ?? []
        let слитые = живые + выбранная.filter { выбор in
            !живые.contains { $0.persistentModelID == выбор.persistentModelID }
        }
        return слитые.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Сроки, которые называют врачи. Четвёртый — «своё»: в карте
    /// у Стича три врача назвали три разных интервала, и список
    /// готовых вариантов обязан иметь выход для четвёртого.
    enum Срок: String, CaseIterable, Identifiable {
        case трёх = "3 нед", четыреШесть = "4–6 нед", четыреВосемь = "4–8 нед", своё = "своё"
        var id: String { rawValue }
        var недели: (от: Int, до: Int)? {
            switch self {
            case .трёх: (3, 3)
            case .четыреШесть: (4, 6)
            case .четыреВосемь: (4, 8)
            case .своё: nil
            }
        }
    }

    @State private var номер = ""
    @State private var дата = Date()
    @State private var врач = ""
    @State private var клиника: Clinic?
    @State private var препарат = ""
    @State private var доза = ""
    @State private var схема = ""
    @State private var длительность = ""
    @State private var форма = ""
    @State private var вес = ""
    /// Фокус поля веса — единственного `.decimalPad` в этом редакторе.
    @FocusState private var весВФокусе: Bool
    @State private var срок: Срок = .четыреШесть
    @State private var своёОт = 4
    @State private var своёДо = 6
    @State private var выдано = ""
    @State private var инструкция = ""
    @State private var происхождение = ""
    @State private var загружено = false
    @State private var удаляем = false
    @State private var показываемВАптеке = false

    private var новое: Bool { prescription == nil }
    private var можноСохранить: Bool {
        !препарат.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Недели из выбора. «Своё» берёт два шаговых поля.
    private var недели: (от: Int, до: Int) {
        срок.недели ?? (min(своёОт, своёДо), max(своёОт, своёДо))
    }

    /// Окно датами — показывается ДО сохранения, на глазах.
    /// `ControlWindow` уже умеет это считать; форма только спрашивает.
    private var окно: ControlWindow.Window? {
        ControlWindow.window(prescribedAt: дата,
                             ControlWindow.Prescribed(fromWeeks: недели.от, toWeeks: недели.до))
    }

    var body: some View {
        TGSheet(title: новое ? "Новое назначение" : "Назначение",
                subtitle: "срок контроля — главное поле: по нему приложение напомнит",
                closeTitle: новое ? "Отмена" : "Закрыть",
                hasUnsavedChanges: новое && (можноСохранить || !номер.isEmpty)) {
            TGCard(spacing: 0) {
                LabeledField(label: "Номер") {
                    // Был номер живого рецепта. Ярлык «Номер» не говорит,
                    // какого именно, — слово-роль говорит и ничего не
                    // выносит наружу. Разбор — `ПодсказкаНеДанныеTests`.
                    TextField("номер рецепта", text: $номер)
                }
                TGDivider()
                DatePicker("Дата", selection: $дата, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Номер нужен в аптеке — он же стоит первым в списке.")
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "что выписано")
                LabeledField(label: "Препарат") {
                    TextField("Левотироксин", text: $препарат)
                }
                TGDivider()
                LabeledField(label: "Доза") {
                    // «0,1 мг» был примером дозы живого назначения.
                    // Информации в нём ровно одна — что единицу пишут
                    // в том же поле, — и она сказана словами. Тот же
                    // ключ стоит у «66 мкг» (Editors) и «16 мг»
                    // (ScheduleChangeSheet): три примера, один формат.
                    TextField("доза с единицей", text: $доза)
                }
                TGDivider()
                LabeledField(label: "Схема") {
                    TextField("утром натощак", text: $схема)
                }
                TGDivider()
                LabeledField(label: "Сколько давать") {
                    TextField("срок", text: $длительность)
                }
                TGDivider()
                LabeledField(label: "Форма") {
                    TextField("таблетки", text: $форма)
                }
                TGExplainer(text: "Форма стоит у рецепта, а не у схемы лечения: вопрос обычно ретроспективный — какая форма была в тот месяц, когда что-то пошло не так.")
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "кто назначил")
                LabeledField(label: "Врач") {
                    TextField("фамилия врача", text: $врач)
                }
                TGDivider()
                Picker("Клиника", selection: $клиника) {
                    Text("не указана").tag(nil as Clinic?)
                    ForEach(доступные) { Text(verbatim: $0.name).tag($0 as Clinic?) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Token.Size.tapTarget)
                if доступные.isEmpty {
                    TGExplainer(text: "Справочник пуст. Клиники и лаборатории заводятся в «Здоровье» → «Клиники и лаборатории» — оттуда они и попадают в этот выбор.")
                }
                // Телефон выписавшей клиники нажимаемым: по рецепту
                // звонят, когда в аптеке чего-то не хватает или когда
                // номер бланка не читается.
                if let номер = Fmt.notBlank(клиника?.phone ?? "") {
                    TGDivider()
                    СтрокаЗвонка(номер: номер)
                }
                TGDivider()
                LabeledField(label: "Откуда взято") {
                    TextField("PDF-ордоннанс, письмо, со слов", text: $происхождение)
                }
                TGExplainer(text: "«Откуда взято» решает споры: назначение, известное только письмом, иначе не отличить от бланка.")
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "вес, от которого считали дозу")
                LabeledField(label: "Вес, кг") {
                    TextField(подсказкаВеса, text: $вес).keyboardType(.decimalPad)
                        .focused($весВФокусе)
                }
                // Вес НЕ подставляется сам, и это не экономия на коде:
                // рецепт часто заводят задним числом, а текущий вес
                // к дате назначения отношения не имеет. Подставь мы его —
                // доза считалась бы от веса, которого в тот день не было,
                // и число выглядело бы введённым человеком.
                TGExplainer(text: "Не подставляем сам: рецепт часто заводят задним числом, а вес с тех пор изменился. Сегодняшний — в подсказке.")
            }

            TGCard {
                TGSectionHeader(title: "контроль через")
                Picker("Срок контроля", selection: $срок) {
                    ForEach(Срок.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if срок == .своё {
                    Stepper(value: $своёОт, in: 0...52) {
                        HStack {
                            Text("от, недель").textStyle(AppFont.body)
                            Spacer()
                            Text(verbatim: String(своёОт)).textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    Stepper(value: $своёДо, in: 0...52) {
                        HStack {
                            Text("до, недель").textStyle(AppFont.body)
                            Spacer()
                            Text(verbatim: String(своёДо)).textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }

                // Окно датами — на глазах, до сохранения: «через 4–6 недель»
                // человек не считает в голове, а именно дата решает,
                // успеет он или нет.
                if let окно {
                    TGDivider()
                    TGListRow(title: "Окно контроля",
                              value: .готовая("\(Fmt.shortDay(окно.opens)) — \(Fmt.shortDay(окно.closes))"),
                              systemImage: "calendar",
                              accessory: .none)
                }

                TGExplainer(text: "Диапазоном, а не датой: Togo не выбирает срок за врача. Напомним в начале окна и в последний день.")
            }

            TGCard(spacing: 0) {
                LabeledField(label: "Выдано") {
                    TextField("сколько и чего", text: $выдано)
                }
                TGDivider()
                TGSectionHeader(title: "инструкция")
                TextField("нанести между лопатками, не купать 24 ч", text: $инструкция, axis: .vertical)
                    .textStyle(AppFont.body)
                    .frame(minHeight: Token.Size.tapTarget)
            }

            if prescription != nil {
                // «Показать в аптеке» — ПЕРЕД удалением и отдельной
                // кнопкой: номер называют вслух или показывают через
                // стекло, и это то, зачем рецепт открывают чаще всего.
                // Долг был объявлен в голове этого файла ещё до экрана;
                // теперь объявление исполнено, а не описано.
                if Fmt.notBlank(номер) != nil {
                    TGButton(title: "Показать в аптеке", variant: .primary, size: .medium,
                             systemImage: "arrow.up.left.and.arrow.down.right") {
                        показываемВАптеке = true
                    }
                }

                TGButton(title: "Удалить назначение", variant: .destructive, size: .medium, systemImage: "trash") {
                    удаляем = true
                }
            }

            // Запас под клавиатуру. Кадр 08.10.2026: при поднятой
            // клавиатуре строка «Препарат» уходит под кнопку «Добавить»,
            // а сегмент сроков и шаговые поля до кадра не доезжают вовсе.
            // Та же семья, что «Норма до» у анализа: высоту съедает
            // то, что появляется ТОЛЬКО во время ввода, и ни узкий
            // экран, ни крупный шрифт этого не ловят.
            Spacer(minLength: Token.Size.tapTarget * 2)
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Форма — по образцу запаса корма (`d569d01`):
            // строка над кнопкой, на ТОЙ ЖЕ величине, что ворота.
            VStack(spacing: Token.Space.s8) {
                if !можноСохранить {
                    Text("Назови препарат — по нему назначение и ищут")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: новое ? "Добавить" : "Сохранить", isEnabled: можноСохранить) { сохранить() }
            }
        }
        .presentationDetents([.large])
        // Выход с цифровой клавиатуры. Тут он дороже обычного: вес,
        // от которого считали дозу, НЕ подставляется сам (решение рядом
        // с полем), то есть это единственное место, где число вводит
        // человек и где потерять ввод значит потерять запись врача.
        .готовоНадКлавиатурой { весВФокусе = false }
        .task { загрузить() }
        .fullScreenCover(isPresented: $показываемВАптеке) {
            PharmacyNumberScreen(номер: номер.trimmingCharacters(in: .whitespaces),
                                 препарат: Fmt.notBlank(препарат),
                                 выдано: Fmt.notBlank(выдано))
        }
        .confirmationDialog("Удалить назначение?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                // Надгробие вместо `context.delete` — см. `Medication.deletedAt`.
                if let prescription {
                    let откат = ОбщееУдаление.удалить(prescription)
                    guard context.persist(otherwise: откат) else {
                        Haptics.warning()
                        appState.showFailure("Не удалилось · нажми ещё раз")
                        return
                    }
                }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вместе с рецептом уйдёт и напоминание о контроле. Записи анализов и визиты останутся.")
        }
    }

    /// Остаётся `String`, и это проверено, а не недосмотр.
    ///
    /// 15.10.2026 рядом чинили `SitterBriefingScreen`, где подсказка
    /// была `String` и из-за этого не локализовалась: `TextField`
    /// выбирает перегрузку по ТИПУ аргумента, и `String` уходит
    /// в `StringProtocol`, который каталог не спрашивает. Здесь это
    /// **верно**: функция возвращает ЧИСЛО — либо вес собаки через
    /// `ЧислоСБланка.показать`, либо образец `"4,1"`. Переводить нечего,
    /// а сделай её `LocalizedStringKey` — вес человека поехал бы
    /// в каталог ключом, как уже случилось с кличкой «Стич»
    /// (`en Stitch`).
    ///
    /// **Не «чинить» по образцу соседа.** Из двух вызовов `TextField`
    /// с переменной в проекте дефектом был один; второй — вот этот.
    private var подсказкаВеса: String {
        guard let вес = dog?.weightKg, вес > 0 else { return "4,1" }
        return ЧислоСБланка.показать(вес)
    }

    private func загрузить() {
        guard !загружено, let prescription else { загружено = true; return }
        номер = prescription.number
        дата = prescription.date
        врач = prescription.doctor
        клиника = prescription.clinic
        препарат = prescription.medicationName
        доза = prescription.dosage
        схема = prescription.schedule
        длительность = prescription.duration
        форма = prescription.pharmacyForm ?? ""
        вес = ЧислоСБланка.текст(prescription.dogWeightKg)
        выдано = prescription.dispensed
        инструкция = prescription.instruction
        происхождение = prescription.source

        // Срок: если он совпал с готовым вариантом — показываем его,
        // иначе «своё». Выводится из значений, а не хранится отдельно:
        // две копии одного решения разошлись бы молча.
        // Сравнение покомпонентно: `(Int, Int)?` не `Equatable`, и `==`
        // на опциональных кортежах не собирается — компилятор поймал
        // это сразу, в отличие от класса ошибок, которые он пропускает.
        let от = prescription.controlFromWeeks
        let до = prescription.controlToWeeks
        срок = Срок.allCases.first { вариант in
            guard let н = вариант.недели else { return false }
            return н.от == от && н.до == до
        } ?? .своё
        своёОт = prescription.controlFromWeeks
        своёДо = prescription.controlToWeeks
        загружено = true
    }

    private func сохранить() {
        let цель = prescription ?? Prescription(number: номер, date: дата, medicationName: препарат)

        let былНомер = цель.number
        let былаДата = цель.date
        let былВрач = цель.doctor
        let былаКлиника = цель.clinic
        let былПрепарат = цель.medicationName
        let былаДоза = цель.dosage
        let былаСхема = цель.schedule
        let былаДлительность = цель.duration
        let былаФорма = цель.pharmacyForm
        let былВес = цель.dogWeightKg
        let былоОт = цель.controlFromWeeks
        let былоДо = цель.controlToWeeks
        let былоВыдано = цель.dispensed
        let былаИнструкция = цель.instruction
        let былоПроисхождение = цель.source
        let былоИзменено = цель.changedAt

        цель.number = номер.trimmingCharacters(in: .whitespaces)
        цель.date = дата
        цель.doctor = врач.trimmingCharacters(in: .whitespaces)
        цель.clinic = клиника
        цель.medicationName = препарат.trimmingCharacters(in: .whitespaces)
        цель.dosage = доза.trimmingCharacters(in: .whitespaces)
        цель.schedule = схема.trimmingCharacters(in: .whitespaces)
        цель.duration = длительность.trimmingCharacters(in: .whitespaces)
        цель.pharmacyForm = Fmt.notBlank(форма)
        цель.dogWeightKg = ЧислоСБланка.разобрать(вес)
        цель.controlFromWeeks = недели.от
        цель.controlToWeeks = недели.до
        цель.dispensed = выдано.trimmingCharacters(in: .whitespaces)
        цель.instruction = инструкция
        цель.source = происхождение.trimmingCharacters(in: .whitespaces)
        цель.changedAt = Date()

        let новая = prescription == nil
        if новая {
            цель.dog = dog
            context.insert(цель)
        }

        guard context.persist(otherwise: {
            if новая {
                цель.dog = nil
                context.delete(цель)
            } else {
                цель.number = былНомер
                цель.date = былаДата
                цель.doctor = былВрач
                цель.clinic = былаКлиника
                цель.medicationName = былПрепарат
                цель.dosage = былаДоза
                цель.schedule = былаСхема
                цель.duration = былаДлительность
                цель.pharmacyForm = былаФорма
                цель.dogWeightKg = былВес
                цель.controlFromWeeks = былоОт
                цель.controlToWeeks = былоДо
                цель.dispensed = былоВыдано
                цель.instruction = былаИнструкция
                цель.source = былоПроисхождение
                цель.changedAt = былоИзменено
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Номер для аптеки

/// Номер рецепта на весь экран, яркость на максимум.
///
/// **Зачем отдельная поверхность, а не крупная строка в форме.**
/// Номер называют вслух или показывают провизору через стекло
/// (`Medical.swift:306` — «по нему в аптеке получают лекарство»),
/// то есть его читает **другой человек, с чужого экрана, в чужом
/// свете**. У формы для этого неверно всё: номер стоит в поле ввода
/// рядом с десятком других полей, кегль тот же, яркость — та, которую
/// хозяйка выставила себе под экономию.
///
/// Поэтому здесь: цифры во всю ширину, монопробельные (чтобы читались
/// по одной и не сбивался счёт при диктовке), и больше ничего крупного
/// рядом.
///
/// **Монопробельные цифры — не украшение.** У пропорциональных единица
/// уже остальных, и в номере `8935331` человек, диктующий вслух, теряет
/// место. Начертание берётся у `AppFont.numeric`, где это уже решено.
///
/// ## Яркость
///
/// `.яркостьНаМаксимум()` — модификатор из `ЯркостьЭкрана.swift`,
/// и возврат там висит на уходе с экрана, сворачивании и возврате
/// из фона, а НЕ на кнопке «Закрыть». Кнопка — одна дорога ухода
/// из четырёх; повесить возврат на неё значило бы починить одну
/// четверть и считать сделанным.
///
/// ## Что показано рядом и почему только это
///
/// Препарат и «выдано» — мелким под номером. Они нужны провизору,
/// чтобы сверить, то ли он выдаёт, и это **единственная причина** их
/// присутствия. Дозы, схемы, срока контроля и клиники здесь нет:
/// аптеке они не нужны, а на экране, который суют чужому человеку,
/// лишняя медицинская подробность — это разглашение без повода.
struct PharmacyNumberScreen: View {
    let номер: String
    var препарат: String?
    var выдано: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Token.Surface.screen.ignoresSafeArea()

            VStack(spacing: Token.Space.s24) {
                Spacer()

                Text("Номер для аптеки")
                    .textStyle(AppFont.caption)
                    .accessibilityHidden(true)

                // Номер — единственное крупное на экране.
                Text(verbatim: номер)
                    .textStyle(AppFont.numeric(48))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .accessibilityLabel(произносимыйНомер)

                if let препарат {
                    Text(verbatim: подпись(препарат))
                        .textStyle(AppFont.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Token.Spacing.screenPadding)
                }

                Spacer()

                TGButton(title: "Закрыть", variant: .secondary, size: .large) { dismiss() }
                    .padding(.horizontal, Token.Spacing.screenPadding)
                    .padding(.bottom, Token.Space.s24)
            }
        }
        .яркостьНаМаксимум()
    }

    private func подпись(_ препарат: String) -> String {
        [препарат, выдано].compactMap { $0 }.joined(separator: " · ")
    }

    /// Номер **по цифрам** для VoiceOver.
    ///
    /// «8935331» синтезатор прочтёт как «восемь миллионов девятьсот
    /// тридцать пять тысяч триста тридцать один» — то есть как число,
    /// а это не число, а код, который человек сверяет с бумажкой.
    /// Пробелы между знаками заставляют читать по одному.
    private var произносимыйНомер: String {
        номер.map(String.init).joined(separator: " ")
    }
}
