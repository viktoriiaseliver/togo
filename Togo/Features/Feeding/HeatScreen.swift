import SwiftUI
import SwiftData

/// Цикл. Календарь, а не медицина: приложение помнит даты и считает
/// средний промежуток, потому что в голове это не держится, а в заметках
/// теряется.
struct HeatScreen: View {
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// От настройки размера текста зависит, строкой или столбцом
    /// раскладывать строку истории и ряд чисел прогноза.
    @Environment(\.dynamicTypeSize) private var размерТекста

    @Query(sort: \HeatRecord.startedAt, order: .reverse) private var allRecords: [HeatRecord]

    @State private var isAdding = false
    @State private var editing: HeatRecord?

    private var records: [HeatRecord] {
        allRecords.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

    private var forecast: HeatCycle.Forecast {
        HeatCycle.forecast(records)
    }

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            CinemaHeader("Цикл", надпись: "календарь", отступы: false)
            if let ongoing = records.first, ongoing.isOngoing {
                ongoingCard(ongoing)
            }
            if records.isEmpty {
                EmptyStateCard(
                    subject: .heat,
                    title: "Записей пока нет",
                    message: "Отметь дату начала — и приложение начнёт считать промежуток. После двух записей оно сможет подсказывать, когда ждать следующую.",
                    actionTitle: canEdit ? "Записать течку" : nil,
                    action: canEdit ? { isAdding = true } : nil
                )
            } else {
                forecastCard
                historyCard
            }
            disclaimer
        }
        .navigationTitle("Цикл")
        .cinemaScreen(экран: .sub("heat"))
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Записать течку")
                }
            }
        }
        .sheet(isPresented: $isAdding) { HeatEditorSheet(dog: dog) }
        .sheet(item: $editing) { record in HeatEditorSheet(record: record, dog: dog) }
    }

    private func ongoingCard(_ record: HeatRecord) -> some View {
        TGBanner(
            tone: .waiting,
            title: "Идёт · день \(record.dayNumber())",
            subtitle: "Обычно около \(Fmt.days(HeatCycle.typicalDurationDays)). На прогулках сейчас внимательнее: кобели чувствуют за километр, и это не про воспитание.",
            systemImage: "calendar.badge.clock"
        )
    }

    private var forecastCard: some View {
        TGCard {
            TGSectionHeader(title: "следующая")
            РядЧисел {
                TGStat(value: forecast.expectedNext.map(Fmt.shortDay) ?? "—",
                       caption: "ждём примерно", size: 20)
                TGStat(value: forecast.daysUntilNext.map { $0 > 0 ? "\($0)" : "—" } ?? "—",
                       caption: "дней осталось", size: 20)
                TGStat(value: forecast.averageIntervalDays.map { "\($0)" } ?? "—",
                       caption: "средний промежуток", size: 20)
            }
            if forecast.isEstimate {
                TGDivider()
                TGExplainer(text: "Пока это ориентир, а не расчёт: у взрослой собаки течка примерно раз в полгода. После второй записи приложение посчитает промежуток по её датам.")
            }
        }
    }

    private var historyCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "было")
            ForEach(records) { record in
                Button { if canEdit { editing = record } } label: {
                    строкаИстории(record)
                }
                .buttonStyle(.plain)
                if record.id != records.last?.id { TGDivider() }
            }
        }
    }

    /// Строка истории: дата с длительностью слева, заметка человека справа.
    ///
    /// **Заметка — свободный текст, и вход у него живой:**
    /// `TextField("что-то заметила", text: $note)` ниже в этом же файле
    /// (`HeatEditorSheet`), сохраняется в `target.note`. То есть длину
    /// задаёт человек, а не мы, и расчёта «влезет» тут быть не может.
    ///
    /// Стояло `lineLimit(1)` без `minimumScaleFactor`, то есть заметка
    /// рубилась в многоточие. На доступных размерах левая колонка
    /// забирает почти всю ширину, и от заметки оставалось одно
    /// многоточие — это уже не читаемость, а потеря: человек не видит
    /// даже, что заметка есть.
    @ViewBuilder
    private func строкаИстории(_ record: HeatRecord) -> some View {
        // Раскладка явным `if`, не `ViewThatFits`: он запрещён красной
        // линией проекта — держит в дереве обе ветки, и озвучка находит
        // по два элемента на один орган.
        Group {
            if размерТекста.isAccessibilitySize {
                // Столбцом: заметке достаётся вся ширина, и она
                // переносится по словам вместо многоточия.
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    датаСДлительностью(record)
                    заметка(record, своейСтрокой: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    датаСДлительностью(record)
                    Spacer(minLength: Token.Space.s8)
                    заметка(record, своейСтрокой: false)
                }
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
        .contentShape(Rectangle())
    }

    /// Дети у обеих раскладок — одни и те же вызовы. Разойдись они,
    /// и ветка, которую реже видят, отстанет молча.
    private func датаСДлительностью(_ record: HeatRecord) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s2) {
            Text(Fmt.shortDay(record.startedAt)).textStyle(AppFont.bodyEmphasis)
            Text(record.isOngoing
                 ? "идёт, день \(record.dayNumber())"
                 : record.dayCount().map { Fmt.days($0) } ?? "")
                .textStyle(AppFont.caption)
        }
    }

    @ViewBuilder
    private func заметка(_ record: HeatRecord, своейСтрокой: Bool) -> some View {
        if let note = record.note, !note.isEmpty {
            // `Text(note)` с переменной типа `String` берёт дословную
            // перегрузку и в каталог не уезжает — это данные человека,
            // и так и надо.
            if своейСтрокой {
                Text(note).textStyle(AppFont.caption).wraps()
            } else {
                // Одна строка на обычных размерах — чтобы вид не поехал.
                // `minimumScaleFactor` при достатке места не делает
                // ничего, а в тесноте показывает больше слов прежде
                // многоточия. Полная заметка достаётся нажатием:
                // строка открывает `HeatEditorSheet`.
                Text(note)
                    .textStyle(AppFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var disclaimer: some View {
        TGExplainer(text: "Это календарь, а не медицинский совет. Вопросы про здоровье, вязку и стерилизацию — к врачу; приложение только помнит даты.")
    }
}

struct HeatEditorSheet: View {
    var record: HeatRecord?
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var hasEnded = false
    @State private var endedAt = Date()
    @State private var note = ""
    @State private var isConfirmingDelete = false
    @State private var loaded = false

    private var isNew: Bool { record == nil }

    var body: some View {
        TGSheet(title: isNew ? "Течка" : .готовая(Fmt.shortDay(startedAt)),
                subtitle: "даты можно поправить когда угодно",
                closeTitle: isNew ? "Отмена" : "Закрыть",
                hasUnsavedChanges: isNew && !note.trimmingCharacters(in: .whitespaces).isEmpty) {
            TGCard(spacing: 0) {
                DatePicker("Началась", selection: $startedAt, in: ...Date(), displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Toggle(isOn: $hasEnded) {
                    Text("Уже закончилась").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if hasEnded {
                    TGDivider()
                    DatePicker("Закончилась", selection: $endedAt, in: startedAt...Date(),
                               displayedComponents: .date)
                        .frame(minHeight: Token.Size.tapTarget)
                }
                TGDivider()
                LabeledField(label: "Заметка") {
                    TextField("что-то заметила", text: $note)
                }
            }
            if !isNew {
                TGButton(title: "Удалить запись", variant: .destructive,
                         size: .medium, systemImage: "trash") { isConfirmingDelete = true }
            }
        } footer: {
            TGButton(title: isNew ? "Записать" : "Сохранить") { save() }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard !loaded else { return }
            if let record {
                startedAt = record.startedAt
                hasEnded = record.endedAt != nil
                endedAt = record.endedAt ?? Date()
                note = record.note ?? ""
            }
            loaded = true
        }
        .confirmationDialog("Удалить запись?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let record { context.delete(record) }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Средний промежуток пересчитается без неё.")
        }
    }

    private func save() {
        // Начало и конец течки — ДНИ, а не моменты: на них стоит день
        // цикла, а на нём «опасные дни». Якорь в полдень — чтобы у второго
        // человека в другом поясе день не уехал на сутки. См. `CalendarDay`.
        let target = record ?? HeatRecord(startedAt: CalendarDay.anchored(startedAt))
        target.startedAt = CalendarDay.anchored(startedAt)
        target.endedAt = hasEnded ? CalendarDay.anchored(endedAt) : nil
        target.note = note.isEmpty ? nil : note
        let новая = record == nil
        if новая {
            target.dog = dog
            context.insert(target)
        }
        guard context.persist(otherwise: {
            if новая { context.delete(target) }
        }) else {
            Haptics.warning()
            return
        }
        Haptics.success()
        dismiss()
    }
}
