import SwiftUI
import SwiftData

/// Здоровье. Вкладки нет, пока лечение выключено.
/// Схему меняет только владелец, остальные видят и исполняют.
struct HealthScreen: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]

    @State private var editing: Medication?
    @State private var isAdding = false

    private var dog: Dog? { dogs.first }

    var body: some View {
        NavigationStack {
            TGScreen {
                if dog?.medications.isEmpty ?? true {
                    EmptyStateCard(
                        systemImage: "pills",
                        title: "Схемы лечения пока нет",
                        message: "Добавь препарат — приложение начнёт напоминать про дозу, держать окно натощак и защищать от двойной дозы. Это бесплатно и работает всегда.",
                        actionTitle: canEdit ? "Добавить препарат" : nil,
                        action: canEdit ? { isAdding = true } : nil
                    )
                } else {
                    ForEach(dog?.medications ?? []) { medication in
                        Button { if canEdit { editing = medication } } label: {
                            MedicationCard(medication: medication, canEdit: canEdit)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                }

                sectionsGrid
                disclaimer
            }
            .navigationTitle("Здоровье")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if canEdit, dog != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isAdding = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Добавить препарат")
                    }
                }
            }
            .sheet(isPresented: $isAdding) { MedicationEditorSheet(dog: dog) }
            .sheet(item: $editing) { medication in
                MedicationEditorSheet(medication: medication, dog: dog)
            }
        }
    }

    /// Схему меняет только владелец. Остальные видят её и отмечают приёмы.
    private var canEdit: Bool { appState.can(.editTreatment) }

    private var sectionsGrid: some View {
        TGCard(spacing: 0) {
            NavigationLink { ProtocolScreen(dog: dog) } label: {
                TGListRow(title: "Протокол контроля", value: "T0 / +4 / +6", systemImage: "timer")
            }
            TGDivider()
            NavigationLink { WeightScreen(dog: dog) } label: {
                TGListRow(title: "Вес и симптомы",
                          value: dog.map { Fmt.weight($0.weightKg) },
                          systemImage: "scalemass")
            }
            TGDivider()
            NavigationLink { CareScreen(dog: dog) } label: {
                TGListRow(title: "Прививки и визиты", systemImage: "syringe")
            }
            TGDivider()
            NavigationLink { VetReportScreen(dog: dog) } label: {
                TGListRow(title: "Отчёт врачу", systemImage: "doc.text")
            }
            TGDivider()
            NavigationLink { ProcedurePrepScreen() } label: {
                TGListRow(title: "Подготовка к процедурам", systemImage: "hand.raised")
            }
        }
        .buttonStyle(.plain)
    }

    /// Дисклеймер лежит здесь, а не в настройках: его читают там, где медицина.
    private var disclaimer: some View {
        NavigationLink { MedicalDisclaimerScreen() } label: {
            TGCard {
                Text("Приложение помогает вести записи и не является медицинским устройством. Диагнозов не ставит, дозировок не назначает.")
                    .textStyle(AppFont.caption)
                Text("Подробнее").textStyle(AppFont.captionEmphasis.color(Token.Action.done))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MedicationCard: View {
    let medication: Medication
    let canEdit: Bool

    var body: some View {
        TGCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("\(medication.name) \(medication.doseText)").textStyle(AppFont.cardTitle)
                    Text(medication.scheduleSummary).textStyle(AppFont.caption)
                }
                Spacer(minLength: Token.Space.s8)
                if medication.isPaused {
                    Text("на паузе").textStyle(AppFont.micro.color(Token.Status.waitingText))
                }
            }
            if let note = medication.cancelledNote {
                TGDivider()
                Text(note).textStyle(AppFont.caption)
            }
            if !canEdit {
                TGExplainer(text: "Схему меняет владелец. Ты видишь её и отмечаешь приёмы.")
            }
        }
    }
}

/// Протокол контроля. Стартует от фактической отметки дозы и считает интервал сам —
/// именно отсутствие строки «доза → забор» дважды приводило к неверному чтению анализов.
struct ProtocolScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var lastDose: DoseRecord? {
        dog?.medications.flatMap(\.doses)
            .filter(\.isGiven)
            .max { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }
    }

    var body: some View {
        TGScreen {
            if let dose = lastDose, let givenAt = dose.givenAt {
                TGCard {
                    Text("T+\(Fmt.duration(now.timeIntervalSince(givenAt)))").textStyle(AppFont.display)
                    Text("Доза дана в \(Fmt.clock(givenAt)) под наблюдением").textStyle(AppFont.caption)
                }
                TGCard(spacing: 0) {
                    ProtocolRow(label: "T0", time: givenAt,
                                title: "доза \(dog?.medications.first?.doseText ?? "")",
                                detail: "отмечено с точностью до минуты", isDone: true)
                    TGDivider()
                    ProtocolRow(label: "+4", time: givenAt.addingTimeInterval(4 * 3600),
                                title: "забор крови", detail: "напомним за 30 минут",
                                isDone: now > givenAt.addingTimeInterval(4 * 3600))
                    TGDivider()
                    ProtocolRow(label: "+6", time: givenAt.addingTimeInterval(6 * 3600),
                                title: "забор крови", detail: "вторая точка, по назначению",
                                isDone: now > givenAt.addingTimeInterval(6 * 3600))
                }
                TGCard {
                    Text("Интервал посчитаем сами").textStyle(AppFont.cardTitle)
                    Text("В отчёте будет строка «доза → забор: \(Fmt.duration(now.timeIntervalSince(givenAt)))». Именно её отсутствие дважды приводило к неверному чтению анализов.")
                        .textStyle(AppFont.caption)
                }
                TGButton(title: "Отметить забор крови", systemImage: "cross.vial") {
                    recordDraw()
                }
            } else {
                TGCard {
                    Text("Протокол начинается с дозы").textStyle(AppFont.cardTitle)
                    Text("Отметь приём препарата — приложение засечёт время и само посчитает +4 и +6 часов.")
                        .textStyle(AppFont.caption)
                }
            }
        }
        .navigationTitle("Протокол")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(tick) { now = $0 }
    }

    private func recordDraw() {
        guard let dog else { return }
        let event = LogEvent(kind: .note, authorName: appState.currentUserName)
        event.note = "Забор крови"
        event.dog = dog
        context.insert(event)
        Haptics.success()
    }
}

private struct ProtocolRow: View {
    let label: String
    let time: Date
    let title: String
    let detail: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Text(label)
                .textStyle(AppFont.numeric(15))
                .fixedSize()
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("\(Fmt.clock(time)) · \(title)").textStyle(AppFont.bodyEmphasis)
                Text(detail).textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Token.Action.done : Token.Ink.faint)
        }
        .padding(.vertical, Token.Space.s10)
    }
}

/// Отчёт врачу собирается из уже записанного: нет ни одного поля
/// «заполните для врача».
struct VetReportScreen: View {
    let dog: Dog?

    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date()
    @State private var language = "RU"

    private var events: [LogEvent] {
        Diary.active(dog?.events ?? []).filter { $0.date >= from && $0.date <= to }
    }

    var body: some View {
        TGScreen {
            TGCard(spacing: 0) {
                DatePicker("С", selection: $from, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                DatePicker("По", selection: $to, in: from..., displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Picker("Язык", selection: $language) {
                    ForEach(["RU", "FR", "EN"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, Token.Space.s8)
            }

            TGCard {
                TGSectionHeader(title: "что войдёт")
                ForEach(contents, id: \.0) { title, count in
                    HStack {
                        Text(title).textStyle(AppFont.body)
                        Spacer()
                        Text("\(count)").textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                    }
                    .frame(minHeight: 34)
                }
                TGExplainer(text: "Ничего не надо вспоминать: всё, что попадёт в отчёт, уже записано в бытовой ленте.")
            }

            ShareLink(
                item: CSVFile(name: "togo-otchet.csv", text: Exporter.csv(events: events)),
                preview: SharePreview("Отчёт Того · CSV")
            ) {
                TGCard {
                    TGListRow(title: "Выгрузить CSV", value: "без подписки", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Отчёт")
        .navigationBarTitleDisplayMode(.large)
    }

    private var contents: [(String, Int)] {
        [
            ("Приёмы и пропуски", events.filter { $0.kind == .dose }.count),
            ("Стул и симптомы", events.filter { $0.kind == .stool || $0.kind == .incident }.count),
            ("Вес и аппетит", events.filter { $0.kind == .weight || $0.kind == .meal }.count),
            ("Занятия", events.filter { $0.kind == .training }.count),
        ]
    }
}

/// Вес. Приложение не считает норму само и не ставит целей по проценту:
/// коридор называет врач.
struct WeightScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @State private var newWeight = ""

    var body: some View {
        TGScreen {
            TGCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(dog.map { Fmt.weight($0.weightKg) } ?? "—").textStyle(AppFont.display)
                    Spacer()
                    if let dog, !dog.isWeightInRange {
                        Text("вне коридора").textStyle(AppFont.caption.color(Token.Status.waitingText))
                    } else {
                        Text("в норме").textStyle(AppFont.caption.color(Token.Action.done))
                    }
                }
                if let low = dog?.targetWeightLow, let high = dog?.targetWeightHigh {
                    Text("цель \(Fmt.weight(low)) — \(Fmt.weight(high)) · поставил врач").textStyle(AppFont.caption)
                }
            }

            TGCard {
                TGSectionHeader(title: "взвесить сейчас")
                HStack(spacing: Token.Space.s12) {
                    TextField("4,1", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .textStyle(AppFont.numeric(24))
                    Text("кг").textStyle(AppFont.caption)
                    TGButton(title: "Записать", size: .medium, fullWidth: false,
                             isEnabled: parsedWeight != nil) { save() }
                }
            }

            TGCard {
                TGSectionHeader(title: "история")
                let history = (dog?.weights ?? []).sorted { $0.date > $1.date }.prefix(12)
                if history.isEmpty {
                    TGExplainer(text: "Пока одно значение — то, что ты ввела при добавлении собаки.")
                } else {
                    ForEach(Array(history)) { entry in
                        HStack {
                            Text(Fmt.shortDay(entry.date)).textStyle(AppFont.caption)
                            Spacer()
                            Text(Fmt.weight(entry.kg)).textStyle(AppFont.numeric(15))
                        }
                        .frame(minHeight: 34)
                    }
                }
            }
        }
        .navigationTitle("Вес")
        .navigationBarTitleDisplayMode(.large)
    }

    private var parsedWeight: Double? {
        Double(newWeight.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let dog, let kg = parsedWeight else { return }
        let entry = WeightEntry(kg: kg)
        entry.dog = dog
        context.insert(entry)
        dog.weightKg = kg
        newWeight = ""
        Haptics.success()
    }
}
