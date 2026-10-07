import SwiftUI
import SwiftData

/// Собака: создать, поправить, удалить.
///
/// Один экран на все три действия — так человеку не надо гадать, где
/// заводится вторая собака и где убирается первая.
struct DogEditorScreen: View {
    /// nil — создаём новую.
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var draft = DogDraft()
    @State private var isConfirmingDelete = false
    @State private var loaded = false

    private var isNew: Bool { dog == nil }

    var body: some View {
        TGScreen {
            TGExplainer(text: "Обязательны только кличка и вес. Остальное можно пропустить и заполнить когда угодно.")

            TGCard(spacing: 0) {
                LabeledField(label: "Кличка") {
                    TextField("Стич", text: $draft.name).textInputAutocapitalization(.words)
                }
                TGDivider()
                LabeledField(label: "Вес") {
                    HStack(spacing: Token.Space.s4) {
                        TextField("4,1", text: $draft.weight).keyboardType(.decimalPad)
                        Text("кг").textStyle(AppFont.caption)
                    }
                }
                TGDivider()
                LabeledField(label: "Порода") {
                    TextField("можно пропустить", text: $draft.breed)
                }
            }

            TGCard {
                Toggle(isOn: $draft.isOnTreatment) {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Собака на лечении").textStyle(AppFont.body)
                        Text("включит вкладку «Здоровье», дозы и окно натощак").textStyle(AppFont.caption)
                    }
                }
            }

            if !isNew {
                TGCard {
                    TGSectionHeader(title: "убрать")
                    TGButton(title: "Удалить собаку", variant: .destructive, size: .medium, systemImage: "trash") {
                        isConfirmingDelete = true
                    }
                    TGExplainer(text: "Вместе с ней исчезнет весь её дневник — одиннадцать видов записей: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки и запас корма. Выгрузить дневник можно в «Настройки → Данные и приватность».")
                }
            }
        } bottom: {
            TGButton(title: isNew ? "Добавить собаку" : "Сохранить", isEnabled: draft.isValid) { save() }
        }
        .navigationTitle(isNew ? "Новая собака" : "Профиль")
        .navigationBarTitleDisplayMode(.large)
        .task { load() }
        .confirmationDialog("Удалить \(dog?.displayName ?? draft.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Исчезнут все одиннадцать видов записей: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки и запас корма. Это нельзя отменить.")
        }
    }

    private func load() {
        guard !loaded, let dog else { loaded = true; return }
        draft.name = dog.name
        draft.weight = String(dog.weightKg).replacingOccurrences(of: ".", with: ",")
        draft.breed = dog.breed ?? ""
        draft.isOnTreatment = dog.isOnTreatment
        loaded = true
    }

    private func save() {
        if let dog {
            let былоИмя = dog.name
            let былВес = dog.weightKg
            let былаПорода = dog.breed
            let былоЛечение = dog.isOnTreatment
            dog.name = draft.name
            dog.weightKg = draft.weightValue ?? dog.weightKg
            dog.breed = draft.breed.isEmpty ? nil : draft.breed
            dog.isOnTreatment = draft.isOnTreatment
            guard context.persist(otherwise: {
                dog.name = былоИмя
                dog.weightKg = былВес
                dog.breed = былаПорода
                dog.isOnTreatment = былоЛечение
            }) else { return неСохранилось() }
        } else {
            let new = draft.makeDog()
            context.insert(new)
            SeedData.attachStarterCare(to: new, context: context)
            // Сохраняем сразу и сразу открываем: заводят вторую собаку,
            // чтобы на неё смотреть, а не чтобы она лежала в списке.
            //
            // Выбор ставится только после удачи: `appState.select` звался
            // после `try?`, и приложение могло открыть собаку, которой
            // нет в хранилище.
            guard context.persist(otherwise: { context.delete(new) }) else {
                return неСохранилось()
            }
            DogOrigin.заведенаЗдесь(new.id)
            appState.select(new)
        }
        Haptics.success()
        dismiss()
    }

    /// Экран остаётся открытым: закрыть его значило бы сказать «готово»
    /// о том, чего в дневнике нет. Введённое никуда не делось — человек
    /// нажимает «Готово» ещё раз.
    private func неСохранилось() {
        Haptics.warning()
        appState.showUndo("Не сохранилось · нажми «Готово» ещё раз")
    }

    /// Удалить собаку.
    ///
    /// Если удалили ту, что была открыта, выбор снимается: `activeDog`
    /// вернёт первую из оставшихся, а не будет держаться за пустоту.
    private func delete() {
        guard let dog else { return }
        let былВыбран = appState.activeDogID
        if appState.activeDogID == dog.id { appState.activeDogID = nil }
        context.delete(dog)
        // Снятый выбор возвращаем: иначе при неудавшемся удалении собака
        // осталась бы в дневнике, но перестала быть открытой — и человек
        // решил бы, что удаление прошло.
        guard context.persist(otherwise: { appState.activeDogID = былВыбран }) else {
            Haptics.warning()
            appState.showUndo("Не удалилось · нажми ещё раз")
            return
        }
        Haptics.warning()
        dismiss()
    }
}

/// Напоминание об уходе: завести своё или убрать лишнее.
struct CareTaskEditorSheet: View {
    var task: CareTask?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var detail = ""
    @State private var intervalDays = 30
    @State private var kind: CareKind = .periodic
    @State private var scheduledDate = Date()
    @State private var remindDaysBefore = 14
    @State private var lastDone: Date?
    @State private var category: CareCategory = .grooming
    @State private var isSeasonal = false
    @State private var seasonStart = 4
    @State private var seasonEnd = 10
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    private var isNew: Bool { task == nil }

    var body: some View {
        TGSheet(
            title: isNew ? "Новое напоминание" : .готовая(title),
            subtitle: "придёт утром вместе с остальным, а не отдельно",
            closeTitle: isNew ? "Отмена" : "Закрыть",
            hasUnsavedChanges: isNew && !title.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            TGCard(spacing: 0) {
                LabeledField(label: "Что делаем") {
                    TextField("Когти", text: $title)
                }
                TGDivider()
                LabeledField(label: "Пояснение") {
                    TextField("когда стучат по полу", text: $detail)
                }
            }

            TGCard {
                TGSectionHeader(title: "какого сорта дело",
                                subtitle: "от этого зависит, как оно себя ведёт")
                TGChipGroup(items: CareKind.allCases, title: \.title,
                            isSelected: { $0 == kind }) { kind = $0 }
                TGExplainer(text: .готовая(kindExplainer))
            }

            switch kind {
            case .daily:
                EmptyView()
            case .periodic:
                TGCard(spacing: 0) {
                    Stepper(value: $intervalDays, in: 1...365) {
                        HStack {
                            Text("Как часто").textStyle(AppFont.body)
                            Spacer()
                            Text("раз в \(Fmt.days(intervalDays))").textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    Toggle(isOn: Binding(get: { lastDone != nil },
                                         set: { lastDone = $0 ? Date() : nil })) {
                        VStack(alignment: .leading, spacing: Token.Space.s2) {
                            Text("Уже делали").textStyle(AppFont.body)
                            Text("иначе срок неизвестен — и приложение так и скажет")
                                .textStyle(AppFont.caption)
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    if lastDone != nil {
                        TGDivider()
                        DatePicker("Последний раз",
                                   selection: Binding(get: { lastDone ?? Date() },
                                                      set: { lastDone = $0 }),
                                   in: ...Date(), displayedComponents: .date)
                            .frame(minHeight: Token.Size.tapTarget)
                    }
                }
            case .dated:
                TGCard(spacing: 0) {
                    DatePicker("Когда", selection: $scheduledDate, displayedComponents: .date)
                        .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    // «Напомним заранее» было написано в пояснении, а на
                    // сколько именно — задать было негде: поле в модели
                    // стояло на четырнадцати днях и не менялось никогда.
                    // Прививку и визит к врачу планируют по-разному.
                    Stepper(value: $remindDaysBefore, in: 0...60, step: 1) {
                        HStack {
                            Text("Напомнить за").textStyle(AppFont.body)
                            Spacer()
                            Text(remindDaysBefore == 0 ? "в день визита" : Fmt.days(remindDaysBefore))
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    Stepper(value: $intervalDays, in: 0...730, step: 30) {
                        HStack {
                            Text("Повторять").textStyle(AppFont.body)
                            Spacer()
                            Text(intervalDays == 0 ? "один раз" : "раз в \(Fmt.days(intervalDays))")
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }

            TGCard {
                TGSectionHeader(title: "куда положить")
                TGChipGroup(items: CareCategory.allCases, title: \.title,
                            isSelected: { $0 == category }) { category = $0 }
            }

            if kind != .daily {
            TGCard {
                Toggle(isOn: $isSeasonal) {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Только в сезон").textStyle(AppFont.body)
                        Text("вне сезона напоминание молчит").textStyle(AppFont.caption)
                    }
                }
                if isSeasonal {
                    HStack {
                        Picker("С", selection: $seasonStart) {
                            ForEach(1...12, id: \.self) { Text(месяц($0)).tag($0) }
                        }
                        Picker("По", selection: $seasonEnd) {
                            ForEach(1...12, id: \.self) { Text(месяц($0)).tag($0) }
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            }

            if !isNew {
                TGButton(title: "Удалить напоминание", variant: .destructive, size: .medium, systemImage: "trash") {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            TGButton(title: isNew ? "Добавить" : "Сохранить",
                     isEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Удалить «\(title)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let task { context.delete(task) }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Напоминание перестанет приходить по утрам. Записи о том, что уже сделано, останутся в истории.")
        }
    }

    private var kindExplainer: String {
        switch kind {
        case .daily:
            String(localized: "Привычка. Просрочки у неё нет — есть серия дней подряд. Зубы чистят каждый день: налёт твердеет за сутки.")
        case .periodic:
            String(localized: "Раз в N дней от последнего раза. Пока ни разу не делали, срок неизвестен, и приложение не станет выдумывать просрочку.")
        case .dated:
            String(localized: "Конкретный день: прививка, визит. Напомним заранее и сдвинем дату на следующий раз.")
        }
    }

    private func месяц(_ number: Int) -> String {
        DateFormatter().monthSymbols?[number - 1].capitalized ?? "\(number)"
    }

    private func load() {
        guard !loaded, let task else { loaded = true; return }
        title = task.title
        detail = task.detail
        kind = task.kind
        intervalDays = task.intervalDays
        scheduledDate = task.scheduledDate ?? Date()
        remindDaysBefore = task.remindDaysBefore
        lastDone = task.lastDone
        category = task.category
        isSeasonal = task.seasonStartMonth != nil
        seasonStart = task.seasonStartMonth ?? 4
        seasonEnd = task.seasonEndMonth ?? 10
        loaded = true
    }

    private func save() {
        let target = task ?? CareTask(title: title, detail: detail, kind: kind,
                                      intervalDays: intervalDays, category: category)
        // Снимок до правки: при отказе сохранения поля обязаны вернуться,
        // иначе экран закроется, а изменённое напоминание останется висеть
        // в памяти, не существуя в хранилище. `rollback()` для этого
        // не годится — измерено, см. `SilentFailureTests`.
        let былоНазвание = target.title
        let былоОписание = target.detail
        let былВид = target.kind
        let былИнтервал = target.intervalDays
        let былаКатегория = target.category
        let былоСделано = target.lastDone
        let былаДата = target.scheduledDate
        let былоЗаранее = target.remindDaysBefore
        let былоНачалоСезона = target.seasonStartMonth
        let былКонецСезона = target.seasonEndMonth

        target.title = title
        target.detail = detail
        target.kind = kind
        target.intervalDays = intervalDays
        target.category = category
        target.lastDone = kind == .daily ? target.lastDone : lastDone
        target.scheduledDate = kind == .dated ? scheduledDate : nil
        target.remindDaysBefore = remindDaysBefore
        target.seasonStartMonth = (isSeasonal && kind != .daily) ? seasonStart : nil
        target.seasonEndMonth = (isSeasonal && kind != .daily) ? seasonEnd : nil
        let новое = task == nil
        if новое {
            target.dog = dog
            context.insert(target)
        }

        guard context.persist(otherwise: {
            if новое {
                target.dog = nil
                context.delete(target)
            } else {
                target.title = былоНазвание
                target.detail = былоОписание
                target.kind = былВид
                target.intervalDays = былИнтервал
                target.category = былаКатегория
                target.lastDone = былоСделано
                target.scheduledDate = былаДата
                target.remindDaysBefore = былоЗаранее
                target.seasonStartMonth = былоНачалоСезона
                target.seasonEndMonth = былКонецСезона
            }
        }) else {
            Haptics.warning()
            appState.showUndo("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}

/// Схема лечения. Меняет её только владелец — остальные видят и исполняют.
struct MedicationEditorSheet: View {
    var medication: Medication?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var doseText = ""
    @State private var times: [Int] = [7 * 60]
    @State private var fastingMinutes = 0
    @State private var fastingBeforeMinutes = 0
    @State private var prescriber = ""
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    private var isNew: Bool { medication == nil }

    var body: some View {
        TGSheet(
            title: isNew ? "Новый препарат" : .готовая(name),
            subtitle: "доза по часам — одна из трёх вещей, которым можно прерывать человека",
            closeTitle: isNew ? "Отмена" : "Закрыть",
            hasUnsavedChanges: isNew && !(name + doseText + prescriber)
                .trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            TGCard(spacing: 0) {
                LabeledField(label: "Название") {
                    TextField("Lévothyrox", text: $name)
                }
                TGDivider()
                LabeledField(label: "Доза") {
                    TextField("66 мкг", text: $doseText)
                }
                TGDivider()
                LabeledField(label: "Назначил") {
                    TextField("врач или клиника", text: $prescriber)
                }
            }

            TGCard {
                TGSectionHeader(title: "во сколько давать")
                ForEach(times.indices, id: \.self) { index in
                    HStack {
                        Picker("Час", selection: Binding(
                            get: { times[index] / 60 },
                            set: { times[index] = $0 * 60 + times[index] % 60 }
                        )) {
                            ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Минуты", selection: Binding(
                            get: { times[index] % 60 },
                            set: { times[index] = (times[index] / 60) * 60 + $0 }
                        )) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        if times.count > 1 {
                            Button {
                                times.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Token.Status.overdueText)
                            }
                            .accessibilityLabel("Убрать время")
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGButton(title: "Добавить время", variant: .secondary, size: .medium, systemImage: "plus") {
                    times.append(19 * 60)
                }
            }

            TGCard {
                // Два окна, а не одно. «Натощак» — это про пустой желудок,
                // а пустым он бывает ДО таблетки; раньше здесь стояла
                // только половина правила, и схема «еда в 20:55, доза
                // в 21:00» проходила проверку целиком.
                Stepper(value: $fastingBeforeMinutes, in: 0...180, step: 15) {
                    HStack {
                        Text("Не кормить до приёма").textStyle(AppFont.body)
                        Spacer()
                        Text(fastingBeforeMinutes == 0 ? "не нужно" : "\(fastingBeforeMinutes) мин")
                            .textStyle(AppFont.numeric(15))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Stepper(value: $fastingMinutes, in: 0...180, step: 15) {
                    HStack {
                        Text("Не кормить после приёма").textStyle(AppFont.body)
                        Spacer()
                        Text(fastingMinutes == 0 ? "не нужно" : "\(fastingMinutes) мин")
                            .textStyle(AppFont.numeric(15))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Пока окно идёт, кнопка еды не исчезает — она объясняет причину и предлагает напомнить, когда можно.")
            }

            if let medication {
                TGCard {
                    Toggle(isOn: Binding(get: { medication.isPaused }, set: { medication.isPaused = $0 })) {
                        Text("Поставить на паузу").textStyle(AppFont.body)
                    }
                    TGExplainer(text: "Пауза оставляет схему в истории и в отчёте врачу — в отличие от удаления.")
                }
                TGButton(title: "Удалить схему", variant: .destructive, size: .medium, systemImage: "trash") {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            TGButton(title: isNew ? "Добавить" : "Сохранить",
                     isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Удалить схему «\(name)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let medication { context.delete(medication) }
                Haptics.warning()
                dismiss()
            }
            Button("Поставить на паузу") {
                medication?.isPaused = true
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Удаление уберёт схему и её приёмы из отчёта врачу. Пауза оставит всё в истории — обычно нужна именно она.")
        }
    }

    private func load() {
        guard !loaded, let medication else { loaded = true; return }
        name = medication.name
        doseText = medication.doseText
        times = medication.times.isEmpty ? [7 * 60] : medication.times
        fastingMinutes = medication.fastingMinutes
        // У схемы, заведённой до появления поля, окно «до» читается
        // симметрично — показываем то же, что и применяем.
        fastingBeforeMinutes = medication.fastingBefore
        prescriber = medication.prescriber ?? ""
        loaded = true
    }

    private func save() {
        let target = medication ?? Medication(name: name, doseText: doseText, times: times, fastingMinutes: fastingMinutes)
        // Снимок до правки. Здесь цена молчания выше, чем у остальных
        // редакторов: часы приёма и окно натощак — это расписание доз
        // и напоминаний. Экран, закрывшийся с «получилось» после
        // несохранённой правки, обещает лечение по новому расписанию,
        // а телефон продолжает напоминать по старому.
        let былоИмя = target.name
        let былаДоза = target.doseText
        let былиЧасы = target.times
        let былоНатощак = target.fastingMinutes
        let былоНатощакДо = target.fastingBeforeMinutes
        let былВрач = target.prescriber

        target.name = name
        target.doseText = doseText
        target.times = times.sorted()
        target.fastingMinutes = fastingMinutes
        target.fastingBeforeMinutes = fastingBeforeMinutes
        target.prescriber = prescriber.isEmpty ? nil : prescriber
        let новое = medication == nil
        if новое {
            target.dog = dog
            context.insert(target)
        }

        guard context.persist(otherwise: {
            if новое {
                target.dog = nil
                context.delete(target)
            } else {
                target.name = былоИмя
                target.doseText = былаДоза
                target.times = былиЧасы
                target.fastingMinutes = былоНатощак
                target.fastingBeforeMinutes = былоНатощакДо
                target.prescriber = былВрач
            }
        }) else {
            Haptics.warning()
            appState.showUndo("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
