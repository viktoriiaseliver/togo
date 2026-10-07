import SwiftUI
import SwiftData

/// Сводка для врача: разворот за минуту.
///
/// Из хендофа (18b): «Сначала цифры, потом дельта словами — врач читает
/// сверху вниз за минуту. Личное закрыто по умолчанию. Два способа
/// отдать: PDF и „показать с телефона“ прямо в кабинете».
///
/// Всё считается из уже записанного. Ни одного поля «заполните для врача»:
/// их не заполняют, а если заполняют — то по памяти, то есть неправдой.
struct VetSummaryScreen: View {
    let dog: Dog?

    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date()
    @State private var showsNotes = false
    @State private var isPresenting = false

    private var doses: [DoseRecord] {
        dog?.medications.flatMap(\.doses) ?? []
    }

    private var weights: [(date: Date, kg: Double)] {
        (dog?.weights ?? []).map { (date: $0.date, kg: $0.kg) }
    }

    private var summary: VetSummary {
        VetSummaryBuilder.build(events: dog?.events ?? [], doses: doses,
                                weights: weights, from: from, to: to)
    }

    /// Тот же по длине период до текущего — чтобы было с чем сравнивать.
    private var previous: VetSummary {
        let span = to.timeIntervalSince(from)
        return VetSummaryBuilder.build(events: dog?.events ?? [], doses: doses,
                                       weights: weights,
                                       from: from.addingTimeInterval(-span), to: from)
    }

    var body: some View {
        TGScreen {
            periodCard
            numbersCard
            weightCard
            deltaCard
            notesCard
            shareCard
        }
        .navigationTitle("Сводка")
        .posterHeader("Сводка")
        .usageScreen(.vetSummary)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $isPresenting) {
            VetSummaryPresentation(summary: summary, delta: deltaLines, dog: dog)
        }
    }

    private var periodCard: some View {
        TGCard(spacing: 0) {
            DatePicker("С", selection: $from, in: ...to, displayedComponents: .date)
                .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            DatePicker("По", selection: $to, in: from...Date(), displayedComponents: .date)
                .frame(minHeight: Token.Size.tapTarget)
        }
    }

    /// Сначала цифры — врач читает их первыми.
    private var numbersCard: some View {
        TGCard {
            HStack(alignment: .top, spacing: Token.Space.s20) {
                if let share = summary.onTimeShare {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("\(Int((share * 100).rounded()))%").textStyle(AppFont.display)
                        Text("доз вовремя").textStyle(AppFont.caption)
                        if summary.dosesShifted > 0 {
                            Text("\(summary.dosesShifted) со сдвигом")
                                .textStyle(AppFont.caption.color(Token.Status.waitingText))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("\(summary.incidentTotal)").textStyle(AppFont.display)
                    Text(String(localized: "\(summary.incidentTotal) инцидентов")
                            .replacingOccurrences(of: "\(summary.incidentTotal) ", with: ""))
                        .textStyle(AppFont.caption)
                    if let detail = summary.incidentDetail {
                        Text(detail).textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if summary.dosesSkipped > 0 {
                TGExplainer(text: "Пропущено осознанно: \(summary.dosesSkipped). Это записи, а не дыры — видно, кто и когда.")
            }
        }
    }

    /// Вес полосами: цифры в ряд читаются хуже, чем форма.
    @ViewBuilder
    private var weightCard: some View {
        if summary.weights.count > 1 {
            TGCard {
                HStack {
                    TGSectionHeader(title: "вес")
                    Spacer()
                    if let delta = summary.weightDelta {
                        Text(delta).textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                }
                WeightBars(points: summary.weights)
            }
        }
    }

    private var deltaLines: [String] {
        VetSummaryBuilder.delta(current: summary, previous: previous)
    }

    @ViewBuilder
    private var deltaCard: some View {
        if !deltaLines.isEmpty {
            TGCard {
                TGSectionHeader(title: "что изменилось с прошлого приёма")
                ForEach(deltaLines, id: \.self) { line in
                    Text(line).textStyle(AppFont.body).wraps()
                }
            }
        }
    }

    /// Личное закрыто по умолчанию — и не уезжает в отчёт.
    private var notesCard: some View {
        TGCard {
            Toggle(isOn: $showsNotes) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Личные заметки").textStyle(AppFont.body)
                    Text("не входят в сводку").textStyle(AppFont.caption)
                }
            }
            if showsNotes {
                let notes = Diary.active(dog?.events ?? [])
                    .filter { $0.kind == .note && $0.date >= from && $0.date <= to }
                if notes.isEmpty {
                    TGExplainer(text: "Заметок за период нет.")
                } else {
                    ForEach(notes) { note in
                        Text("\(Fmt.shortDay(note.date)) · \(note.note ?? "")")
                            .textStyle(AppFont.caption).wraps()
                    }
                }
            }
        }
    }

    private var shareCard: some View {
        TGCard(spacing: 0) {
            Button { isPresenting = true } label: {
                TGListRow(title: "Показать с телефона", systemImage: "iphone", accessory: .none)
            }
            .buttonStyle(.plain)
            TGDivider()
            ShareLink(item: VetSummaryText.plain(summary, delta: deltaLines, dog: dog)) {
                TGListRow(title: "Отправить текстом", systemImage: "square.and.arrow.up",
                          accessory: .none)
            }
            .buttonStyle(.plain)
            TGDivider()
            ShareLink(
                item: CSVFile(name: "togo-svodka.csv",
                              text: Exporter.csv(events: Diary.active(dog?.events ?? [])
                                  .filter { $0.date >= from && $0.date <= to })),
                preview: SharePreview("Сводка Togo · CSV")
            ) {
                TGListRow(title: "Выгрузить CSV", value: "без подписки",
                          systemImage: "tablecells", accessory: .none)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Полосы веса. Форма читается быстрее ряда цифр — врачу нужен именно
/// наклон, а не значения по одному.
struct WeightBars: View {
    let points: [(date: Date, kg: Double)]

    private var range: (low: Double, high: Double) {
        let values = points.map(\.kg)
        let low = (values.min() ?? 0) - 0.2
        let high = (values.max() ?? 1) + 0.2
        return (low, max(high, low + 0.1))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Token.Space.s6) {
            ForEach(Array(points.suffix(8).enumerated()), id: \.offset) { _, point in
                VStack(spacing: Token.Space.s4) {
                    Text(Fmt.decimal(point.kg))
                        .textStyle(AppFont.micro)
                        .fixedSize()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Token.Action.doneQuiet)
                        .frame(height: height(point.kg))
                    Text(Fmt.shortDay(point.date))
                        .textStyle(AppFont.micro.color(Token.Ink.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.map { "\(Fmt.shortDay($0.date)) \(Fmt.weight($0.kg))" }
                                .joined(separator: ", "))
    }

    private func height(_ kg: Double) -> CGFloat {
        let share = (kg - range.low) / (range.high - range.low)
        return max(6, 70 * share)
    }
}

/// «Показать с телефона» — крупно, прямо в кабинете.
struct VetSummaryPresentation: View {
    let summary: VetSummary
    let delta: [String]
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGScreen {
            Text(dog.map { "\($0.displayName) · \(Fmt.weight($0.weightKg))" } ?? "")
                .textStyle(AppFont.cardTitle)
            Text("\(Fmt.shortDay(summary.from)) — \(Fmt.shortDay(summary.to))")
                .textStyle(AppFont.caption)

            if let share = summary.onTimeShare {
                TGCard {
                    Text("\(Int((share * 100).rounded()))% доз вовремя").textStyle(AppFont.display)
                    if summary.dosesShifted > 0 {
                        Text("\(summary.dosesShifted) со сдвигом · пропущено \(summary.dosesSkipped)")
                            .textStyle(AppFont.body)
                    }
                }
            }

            TGCard {
                Text("\(summary.incidentTotal) \(String(localized: "\(summary.incidentTotal) инцидентов").replacingOccurrences(of: "\(summary.incidentTotal) ", with: ""))")
                    .textStyle(AppFont.display)
                if let detail = summary.incidentDetail {
                    Text(detail).textStyle(AppFont.body)
                }
            }

            if summary.weights.count > 1 {
                TGCard {
                    if let delta = summary.weightDelta {
                        Text(delta).textStyle(AppFont.cardTitle)
                    }
                    WeightBars(points: summary.weights)
                }
            }

            ForEach(delta, id: \.self) { line in
                Text(line).textStyle(AppFont.body).wraps()
            }
        }
        .safeAreaInset(edge: .bottom) {
            TGButton(title: "Закрыть", variant: .secondary) { dismiss() }
                .padding(Token.Spacing.screenPadding)
        }
    }
}

/// Тот же текст, но одной строкой — чтобы отправить в мессенджер.
nonisolated enum VetSummaryText {
    @MainActor
    static func plain(_ summary: VetSummary, delta: [String], dog: Dog?) -> String {
        var lines: [String] = []
        if let dog { lines.append("\(dog.displayName), \(Fmt.weight(dog.weightKg))") }
        lines.append(String(localized: "Период: \(Fmt.shortDay(summary.from)) — \(Fmt.shortDay(summary.to))"))

        if let share = summary.onTimeShare {
            lines.append("Доз вовремя: \(Int((share * 100).rounded()))% из \(summary.totalDoses)"
                         + (summary.dosesShifted > 0 ? String(localized: ", со сдвигом \(summary.dosesShifted)") : "")
                         + (summary.dosesSkipped > 0 ? String(localized: ", пропущено \(summary.dosesSkipped)") : ""))
        }
        if summary.incidentTotal > 0 {
            lines.append(String(localized: "Инциденты: \(summary.incidentTotal)")
                         + (summary.incidentDetail.map { " (\($0))" } ?? ""))
        }
        if let weight = summary.weightDelta { lines.append(String(localized: "Вес: \(weight)")) }
        lines.append(contentsOf: delta)
        return lines.joined(separator: "\n")
    }
}
