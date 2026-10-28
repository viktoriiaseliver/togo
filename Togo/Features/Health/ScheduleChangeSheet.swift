import SwiftUI
import SwiftData

/// Врач изменил дозу.
///
/// Из хендофа (17c): «Старое и новое рядом, перечёркнуто только старое.
/// Вопрос „с какого момента“ задан явно — это место, где семьи чаще всего
/// ошибаются в первый день новой схемы».
struct ScheduleChangeSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var doseText: String = ""
    @State private var times: [Int] = []
    @State private var startsFrom: ScheduleChange.StartsFrom = .tomorrowMorning
    @State private var now = Date()

    private var change: ScheduleChange {
        ScheduleChange(oldDoseText: medication.doseText, oldTimes: medication.times,
                       newDoseText: doseText, newTimes: times, startsFrom: startsFrom)
    }

    private var doomed: [DoseRecord] {
        change.doomedDoses(medication.doses, now: now)
    }

    /// Право менять схему лечения.
    ///
    /// **Этого вопроса здесь не задавали вовсе — замер 28.10.2026.**
    /// Право `.editTreatment` спрашивают шесть экранов «Здоровья»
    /// (визиты, диагнозы, клиники, анализы, рецепты, документы),
    /// а лист, которым МЕНЯЮТ САМУ СХЕМУ, не спрашивал: гость
    /// с ролью «только смотреть» мог поменять дозу лекарства.
    ///
    /// > Право проверяли везде, где схему ПОКАЗЫВАЮТ, и не проверили
    /// > там, где её МЕНЯЮТ. Дыра была не в правиле, а в одном
    /// > месте, которое под него не попало.
    ///
    /// `.editTreatment` по умолчанию есть только у владельца
    /// (`FamilyResolver`), и у второго телефона оно отнимается — то есть
    /// путь не краевой: это основной путь любого приглашённого.
    private var canEdit: Bool { appState.can(.editTreatment) }

    var body: some View {
        TGSheet(title: "Врач изменил дозу",
                subtitle: "прошлые отметки останутся как были — меняется только план вперёд",
                hasUnsavedChanges: isChanged) {
            if !canEdit { ПлашкаПрава(право: .editTreatment) }
            comparison
            timesCard
            startCard
            consequenceCard
        } footer: {
            // Правило круга 5, п. 1. Ворота здесь особенные: кнопка
            // выключена не из-за пустого поля, а потому что менять
            // пока НЕЧЕГО — доза и часы те же, что были. Из тусклой
            // кнопки это читается как поломка, а не как «ты ещё
            // ничего не изменил»; «с какого момента» в ворота
            // не входит нарочно — сам по себе он ничего не меняет.
            if !isChanged {
                Text("Поменяй дозу или часы — пока менять нечего")
                    .textStyle(AppFont.caption.color(Token.Status.overdueText))
                    .wraps()
            }
            TGButton(title: "Сохранить новую схему",
                     isEnabled: isChanged && canEdit) { save() }
            TGButton(title: "Отменить", variant: .secondary, size: .medium) { dismiss() }
        }
        .presentationDetents([.large])
        .onAppear {
            doseText = medication.doseText
            times = medication.times.sorted()
        }
    }

    private var isChanged: Bool {
        doseText != medication.doseText || times.sorted() != medication.times.sorted()
    }

    /// Старое и новое рядом. Перечёркнуто только старое.
    private var comparison: some View {
        TGCard(spacing: 0) {
            HStack(alignment: .top, spacing: Token.Space.s12) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    TGSectionHeader(title: "было")
                    Text(medication.doseText)
                        .textStyle(AppFont.cardTitle.color(Token.Ink.secondary))
                        .strikethrough(isChanged, color: Token.Ink.secondary)
                    Text(ScheduleChange.summary(medication.times))
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                        .strikethrough(isChanged, color: Token.Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    TGSectionHeader(title: "стало")
                    Text(doseText.isEmpty ? "—" : doseText).textStyle(AppFont.cardTitle)
                    Text(ScheduleChange.summary(times)).textStyle(AppFont.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Token.Space.s4)

            TGDivider()
            HStack {
                Text("Доза").textStyle(AppFont.body)
                Spacer()
                TextField("доза с единицей", text: $doseText)
                    .multilineTextAlignment(.trailing)
                    .textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)
        }
    }

    private var timesCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "когда давать")
            ForEach(Array(times.enumerated()), id: \.offset) { index, minute in
                HStack {
                    DatePicker("Приём \(index + 1)", selection: Binding(
                        get: { dateFrom(minute) },
                        set: { times[index] = minuteOf($0) }
                    ), displayedComponents: .hourAndMinute)
                    .textStyle(AppFont.body)
                    Button {
                        times.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Token.Status.overdueText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать приём \(index + 1)")
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
            }
            Button {
                times.append(9 * 60)
                times.sort()
            } label: {
                TGListRow(title: "Добавить приём", systemImage: "plus", accessory: .none)
            }
            .buttonStyle(.plain)
        }
    }

    private var startCard: some View {
        TGCard {
            TGSectionHeader(title: "с какого момента")
            Picker("С какого момента", selection: $startsFrom) {
                ForEach(ScheduleChange.StartsFrom.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .pickerStyle(.segmented)
            TGExplainer(text: startsFrom == .tomorrowMorning
                        ? "Вечером — ещё старая схема. Врач сказал иначе? Переключи."
                        : "Новая схема действует с этой минуты.")
        }
    }

    /// Что произойдёт — до нажатия, а не после.
    private var consequenceCard: some View {
        TGCard {
            TGSectionHeader(title: "пересчитать напоминания")
            if doomed.isEmpty {
                TGExplainer(text: "Уже заведённые отметки останутся на месте.")
            } else {
                ForEach(doomed) { dose in
                    HStack {
                        Text("\(Fmt.clock(dose.scheduledAt)) удалится").textStyle(AppFont.body)
                        Spacer()
                        Image(systemName: "trash").foregroundStyle(Token.Status.overdueText)
                    }
                    .frame(minHeight: 34)
                }
            }
            TGExplainer(text: "Данные и пропущенные дозы не трогаем: история приёмов задним числом не должна становиться неправдой.")
        }
    }

    private func dateFrom(_ minute: Int) -> Date {
        Calendar.current.date(minuteOfDay: minute, on: Date())
    }

    private func minuteOf(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func save() {
        // Ворота права — ЗДЕСЬ, а не только у кнопки. Выключенная
        // кнопка — это подсказка глазу; она не защищает от второго
        // пути к тому же действию, а записи о смене схемы уезжают
        // семье. Форма отказа взята у `EventLog` — там же, где
        // проверяется право на запись в дневник.
        guard canEdit else {
            appState.showFailure(String(localized: "Это записывает тот, кому разрешено"))
            Haptics.warning()
            return
        }
        // Имя автора — обязательное, не для порядка: запись о смене
        // схемы уезжает семье, а безымянная наружу не уходит вовсе
        // (красная линия проекта). И второй человек должен видеть,
        // КТО поменял дозу, — это первое, что он спросит.
        guard let removed = ScheduleChangeApplier.apply(change, to: medication,
                                                        now: now, context: context,
                                                        автор: appState.currentUserName) else {
            Haptics.warning()
            return
        }
        Haptics.success()
        _ = removed
        dismiss()
    }
}
