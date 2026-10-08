import SwiftUI
import SwiftData

/// Здоровье. Вкладки нет, пока лечение выключено.
/// Схему меняет только владелец, остальные видят и исполняют.
struct HealthScreen: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var allMedications: [Medication]

    @Environment(\.modelContext) private var context
    @State private var editing: Medication?
    @State private var isAdding = false
    @State private var isFinishing = false
    @State private var changingSchedule: Medication?
    @State private var countingPills: Medication?

    private var dog: Dog? { appState.activeDog(from: dogs) }

    private var medications: [Medication] {
        guard let dog else { return [] }
        return allMedications.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

    var body: some View {
        NavigationStack {
            TGScreen {
                if medications.isEmpty {
                    EmptyStateCard(
                        subject: .health,
                        title: "Схемы лечения пока нет",
                        message: "Добавь препарат — приложение начнёт напоминать про дозу, держать окно натощак и защищать от двойной дозы. Это бесплатно и работает всегда.",
                        actionTitle: canEdit ? "Добавить препарат" : nil,
                        action: canEdit ? { isAdding = true } : nil
                    )
                } else {
                    ForEach(medications) { medication in
                        VStack(spacing: Token.Space.s8) {
                            Button { if canEdit { editing = medication } } label: {
                                MedicationCard(medication: medication, canEdit: canEdit)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit)

                            if canEdit { medicationActions(medication) }
                        }
                    }
                }

                sectionsGrid
                finishCourse
                disclaimer
            }
            .navigationTitle("Здоровье")
            .posterHeader("Здоровье")
            .usageScreen(.health)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                SettingsToolbarItem()
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
            .sheet(item: $changingSchedule) { medication in
                ScheduleChangeSheet(medication: medication)
            }
            .sheet(item: $countingPills) { medication in
                PillSupplyScreen(medication: medication, courseEnds: medication.courseEnd)
            }
            .sheet(isPresented: $isFinishing) {
                if let dog {
                    CourseFinishSheet(
                        dog: dog,
                        summary: TreatmentCourse.summary(dog),
                        farewell: TreatmentCourse.farewell(dog),
                        onFinish: { finish() },
                        onScheduleCheckup: { days in
                            TreatmentCourse.scheduleCheckup(for: dog, after: days, context: context)
                        }
                    )
                }
            }
        }
    }

    /// Схему меняет только владелец. Остальные видят её и отмечают приёмы.
    private var canEdit: Bool { appState.can(.editTreatment) }

    /// Два действия, ради которых чаще всего и открывают препарат:
    /// врач поменял схему и таблетки кончаются. Оба лежали глубоко
    /// в форме правки — то есть их не было.
    @ViewBuilder
    private func medicationActions(_ medication: Medication) -> some View {
        HStack(spacing: Token.Space.s8) {
            Button { changingSchedule = medication } label: {
                TGCard { TGListRow(title: "Врач изменил дозу",
                                   systemImage: "arrow.triangle.swap", accessory: .none) }
            }
            .buttonStyle(.plain)

            let уровень = PillSupplyAdvisor.level(supply(medication))
            Button { countingPills = medication } label: {
                TGCard {
                    TGListRow(title: "Запас",
                              value: .готовая(supplyValue(medication)),
                              systemImage: "shippingbox",
                              accessory: .none,
                              tone: уровень == .ok ? Token.Ink.primary : уровень.цветТекста)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Курс передаётся обоим местам, а не одному.
    ///
    /// `shortfallDays` считал верно и был покрыт тестами, но живьём
    /// не срабатывал ни разу: тесты передавали дату аргументом сами,
    /// а экран передать её не мог — поля у препарата не было. Строка
    /// «Курс идёт до … — не хватит …» не показывалась никому.
    ///
    /// Расход — СУММА доз (`dailyUse`), а не число приёмов.
    ///
    /// Полтаблетки дважды в день уходят по одной таблетке в сутки,
    /// а не по две. Прежний `max(1, times.count)` ошибался бы в сторону
    /// «хватит дольше» — человек не купил бы вовремя, ровно тот случай,
    /// ради которого счётчик и завели. Пока в `doseSlotsData` не писал
    /// ни один экран, числа совпадали; первая записанная половинка
    /// включила бы ошибку молча.
    ///
    /// **Отсюда же `nil` у препарата без расписания.** Пустое `schedule`
    /// даёт нулевой расход, и запас честно отвечает «не считаем» вместо
    /// прежней единицы в день. Выдумывать расход там, где схемы нет,
    /// значит называть срок, которого никто не назначал.
    private func supply(_ medication: Medication) -> PillSupply? {
        PillSupplyAdvisor.supply(remaining: medication.remaining,
                                 packSize: medication.packSize,
                                 perDay: medication.dailyUse,
                                 courseEnds: medication.courseEnd)
    }

    private func supplyValue(_ medication: Medication) -> String {
        guard let supply = supply(medication) else { return String(localized: "не считаем") }
        return String(localized: "на \(Fmt.days(supply.days))")
    }

    /// Курс кончается здесь, а не тумблером в профиле, где его никто
    /// не найдёт. Вместе с курсом уходит и вкладка — медицина не должна
    /// занимать место у здоровой собаки.
    @ViewBuilder
    private var finishCourse: some View {
        if canEdit, dog != nil {
            Button { isFinishing = true } label: {
                TGCard {
                    TGListRow(title: "Курс завершён", value: "спрячет вкладку",
                              systemImage: "checkmark.seal")
                    TGExplainer(text: "Записи останутся в истории и в отчёте врачу. Вернуть курс можно в профиле.")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func finish() {
        guard let dog else { return }
        TreatmentCourse.finish(dog, by: appState.currentUserName, context: context)
        appState.showUndo("Курс завершён")
        Haptics.success()
    }

    /// Сколько анализов у собаки — в строке раздела, а не внутри него.
    /// Пусто, когда ни одного: «0» рядом с названием читается как
    /// неисправность, а отсутствие числа — как «ещё не заводили».
    private var анализовВсего: LocalizedStringKey? {
        guard let dog, !dog.labResults.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.labResults.count))
    }

    private var визитовВсего: LocalizedStringKey? {
        guard let dog, !dog.vetVisits.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.vetVisits.count))
    }

    private var диагнозовВсего: LocalizedStringKey? {
        guard let dog, !dog.diagnoses.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.diagnoses.count))
    }

    private var назначенийВсего: LocalizedStringKey? {
        guard let dog, !dog.prescriptions.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.prescriptions.count))
    }

    private var sectionsGrid: some View {
        TGCard(spacing: 0) {
                        TGLink(title: "Протокол контроля", value: "T0 / +4 / +6", systemImage: "timer") { ProtocolScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Вес и симптомы", value: dog.map { .готовая(Fmt.weight($0.weightKg)) }, systemImage: "scalemass") { WeightScreen(dog: dog) }
            TGDivider()
            // МЕСТО ВЫЗОВА. Без этой строки экран анализов существует
            // и недостижим: до 08.10.2026 `LabResult` создавался только
            // в `MedicalRecordGallery`, а она целиком под `#if DEBUG`.
            // Модель, обмен, архив и карточки были, а человек не мог
            // завести ни одной записи — то есть поверхность была
            // подключена на ноль мест. Сторож на эту строку —
            // `ДорогаКАнализамTests`, от запрета.
                        TGLink(title: "Анализы", value: анализовВсего, systemImage: "testtube.2") { LabResultsScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Визиты к врачу", value: визитовВсего, systemImage: "stethoscope") { VetVisitsScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Диагнозы", value: диагнозовВсего, systemImage: "questionmark.circle") { DiagnosesScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Назначения", value: назначенийВсего, systemImage: "doc.text") { PrescriptionsScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Прививки и визиты", systemImage: "syringe") { CareScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Сводка врачу", value: "разворот за минуту", systemImage: "doc.text") { VetSummaryScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Выгрузка записей", systemImage: "tablecells") { VetReportScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Подготовка к процедурам", systemImage: "hand.raised") { ProcedurePrepScreen() }
        }
        .buttonStyle(.plain)
    }

    /// Дисклеймер лежит здесь, а не в настройках: его читают там, где медицина.
    private var disclaimer: some View {
        NavigationLink { MedicalDisclaimerScreen() } label: {
            TGCard {
                Text("Приложение помогает вести записи и не является медицинским устройством. Диагнозов не ставит, дозировок не назначает.")
                    .textStyle(AppFont.caption)
                Text("Подробнее").textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
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
                    Text("В отчёте будет строка «доза → забор: \(Fmt.duration(now.timeIntervalSince(givenAt)))». Без этой строки анализы уже дважды читали неверно.")
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
        .posterHeader("Протокол")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(tick) { now = $0 }
    }

    private func recordDraw() {
        EventLog(context: context, appState: appState)
            .record(.note, dog: dog, confirmation: "Записано · забор крови") { event in
                event.note = "Забор крови"
            }
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
                .foregroundStyle(isDone ? Token.Action.doneText : Token.Ink.secondary)
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
                preview: SharePreview("Отчёт Togo · CSV")
            ) {
                TGCard {
                    TGListRow(title: "Выгрузить CSV", value: "без подписки", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Отчёт")
        .posterHeader("Отчёт")
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
    @Environment(AppState.self) private var appState
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
                        Text("в норме").textStyle(AppFont.caption.color(Token.Action.doneText))
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
                        Button { removing = entry } label: {
                            HStack {
                                Text(Fmt.shortDay(entry.date)).textStyle(AppFont.caption)
                                Spacer()
                                Text(Fmt.weight(entry.kg)).textStyle(AppFont.numeric(15))
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    // Взвешивание — единственное, что нельзя было исправить.
                    // Опечатка «12,4 → 124» оставалась в графике навсегда
                    // и уводила коридор веса вместе с собой.
                    TGExplainer(text: "Ошиблась — тапни по строке и удали.")
                }
            }
        }
        .navigationTitle("Вес")
        .posterHeader("Вес")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Удалить взвешивание?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible,
                            presenting: removing) { entry in
            Button("Удалить", role: .destructive) { delete(entry) }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: { entry in
            Text("\(Fmt.shortDay(entry.date)) · \(Fmt.weight(entry.kg)). Из графика и из коридора веса запись тоже уйдёт.")
        }
    }

    /// Удалить взвешивание, вернув текущий вес к предыдущему замеру.
    private func delete(_ entry: WeightEntry) {
        guard let dog else { return }
        context.delete(entry)
        // Текущий вес показывается по всему приложению — если удалили
        // последнее взвешивание, он обязан откатиться, а не остаться
        // от только что стёртой записи.
        let былВес = dog.weightKg
        let rest = dog.weights.filter { $0.persistentModelID != entry.persistentModelID }
        if let latest = rest.max(by: { $0.date < $1.date }) {
            dog.weightKg = latest.kg
        }
        guard context.persist(otherwise: { dog.weightKg = былВес }) else {
            Haptics.warning()
            return appState.showUndo("Взвешивание не удалилось · попробуй ещё раз")
        }
        Haptics.warning()
        removing = nil
    }

    /// Какую запись предлагается удалить.
    @State private var removing: WeightEntry?

    private var parsedWeight: Double? {
        Double(newWeight.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let dog, let kg = parsedWeight else { return }
        let entry = WeightEntry(kg: kg)
        entry.dog = dog
        context.insert(entry)
        dog.weightKg = kg

        // Взвесили — значит, напоминание «Взвесить» отработало. Просить
        // человека отметить то же самое второй раз незачем.
        let задача = dog.careTasks.first { $0.title == "Взвесить" }
        let былоСделано = задача?.lastDone
        задача?.markDone()

        guard context.persist(otherwise: {
            context.delete(entry)
            задача?.lastDone = былоСделано
        }) else {
            Haptics.warning()
            return appState.showUndo("Вес не записался · попробуй ещё раз")
        }
        newWeight = ""
        Haptics.success()
    }
}
