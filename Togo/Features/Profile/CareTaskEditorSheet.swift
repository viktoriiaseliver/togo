import SwiftUI
import SwiftData

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
            // «придёт утром» было верно, пока час сводки выбирался
            // из 5…12. С 28.10.2026 выбирается часть дня — и строка
            // обещала бы утро тому, кто поставил вечер.
            subtitle: "придёт в выбранный час вместе с остальным, а не отдельно",
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
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Образец формы — запас корма (`d569d01`):
            // строка над кнопкой, той же величиной, что и ворота.
            VStack(spacing: Token.Space.s8) {
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Назови напоминание — под этим именем оно встанет в список")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: isNew ? "Добавить" : "Сохранить",
                         isEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Удалить «\(title)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                // Надгробие вместо `context.delete`: иначе у второго
                // человека дело остаётся, и «план дня» у двоих разный.
                if let task {
                    let откат = ОбщееУдаление.удалить(task)
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
        Self.месяцы.indices.contains(number - 1) ? Self.месяцы[number - 1] : "\(number)"
    }

    /// Названия месяцев — один раз на процесс, а не новый `DateFormatter`
    /// на каждый из 24 пунктов двух `Picker` при каждой перерисовке
    /// (04.11.2026). Локаль та же, что была: `DateFormatter()` без
    /// настройки берёт `Locale.current`, а она меняется только с
    /// перезапуском.
    private static let месяцы: [String] =
        (DateFormatter().monthSymbols ?? []).map(\.capitalized)

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
            appState.showFailure("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
