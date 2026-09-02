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

    var body: some View {
        TGSheet(title: "Врач изменил дозу",
                subtitle: "прошлые отметки останутся как были — меняется только план вперёд",
                hasUnsavedChanges: isChanged) {
            comparison
            timesCard
            startCard
            consequenceCard
        } footer: {
            TGButton(title: "Сохранить новую схему", isEnabled: isChanged) { save() }
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
                        .textStyle(AppFont.cardTitle.color(Token.Ink.faint))
                        .strikethrough(isChanged, color: Token.Ink.faint)
                    Text(ScheduleChange.summary(medication.times))
                        .textStyle(AppFont.caption.color(Token.Ink.faint))
                        .strikethrough(isChanged, color: Token.Ink.faint)
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
                TextField("16 мг", text: $doseText)
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
        let removed = ScheduleChangeApplier.apply(change, to: medication, now: now, context: context)
        Haptics.success()
        _ = removed
        dismiss()
    }
}
