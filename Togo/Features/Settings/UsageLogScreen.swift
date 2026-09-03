import SwiftUI

/// Журнал действий: что человек делал в приложении и где оно ему мешало.
///
/// Экран нужен через две недели живого пользования, а не каждый день:
/// сесть, прочитать «что чинить» и починить. Поэтому он не на виду —
/// он в «Данных», рядом с выгрузкой и удалением, где ему и место.
struct UsageLogScreen: View {
    @State private var report = UsageReport.build([])
    @State private var entries: [UsageLog.Entry] = []
    /// Файл журнала целиком — для «Поделиться». Держим в состоянии,
    /// а не читаем в теле: тело пересчитывается на каждый тап, а файл
    /// это тысячи строк с диска.
    @State private var raw = ""
    @State private var isOn = UsageLog.isOn
    @State private var isConfirmingClear = false
    @State private var expanded: String?

    var body: some View {
        TGScreen {
            if report.isEmpty {
                TGBanner(tone: .waiting, title: "Журнал пока пуст",
                         subtitle: isOn
                            ? "Он заполняется сам, пока приложением пользуются. Возвращайся через пару недель."
                            : "Журнал выключен — приложение ничего не записывает о действиях.",
                         systemImage: "text.magnifyingglass")
            } else {
                summary
                frictions
                topActions
                recordKinds
                screens
                days
                sessions
            }
            controls
            privacy
        }
        .navigationTitle("Журнал действий")
        .navigationBarTitleDisplayMode(.large)
        .task { await reload() }
        .usageScreen(.usageLog)
        .confirmationDialog("Очистить журнал?", isPresented: $isConfirmingClear,
                            titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                UsageLog.clear()
                Task { await reload() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи дневника это не тронет — только историю нажатий.")
        }
    }

    /// Читаем и считаем не на главном потоке: за две недели в журнале
    /// набираются тысячи строк, и разбор их в теле экрана — это застывший
    /// интерфейс ровно на том экране, который заведён ради отзывчивости.
    private func reload() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            let entries = UsageLog.entries()
            return (entries, UsageReport.build(entries), UsageLog.rawText())
        }.value
        entries = loaded.0
        report = loaded.1
        raw = loaded.2
    }

    // MARK: Сводка

    private var summary: some View {
        TGCard {
            Text("с \(Fmt.shortDay(report.from)) по \(Fmt.shortDay(report.to))")
                .textStyle(AppFont.cardTitle)
            Text("\(Fmt.days(report.days)) пользования")
                .textStyle(AppFont.caption)
            TGDivider()
            HStack(spacing: 0) {
                TGStat(value: "\(report.total)", caption: "действий")
                TGStat(value: "\(report.records)", caption: "записей")
                TGStat(value: "\(report.sessions.count)", caption: "сеансов")
            }
            TGDivider()
            Text(summaryLine).textStyle(AppFont.caption)
        }
    }

    private var summaryLine: String {
        var parts = ["\(Fmt.decimal((report.recordsPerDay * 10).rounded() / 10)) записей в день"]
        if report.averageSessionLength > 0 {
            parts.append("сеанс в среднем \(Fmt.duration(report.averageSessionLength))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Что чинить

    @ViewBuilder
    private var frictions: some View {
        if report.frictions.isEmpty {
            TGBanner(tone: .done, title: "Ни одного трения не нашлось",
                     subtitle: "Ни отмен сразу после записи, ни двойных тапов, ни сбоев. Это хорошо — но проверь, что журнал включён и данных набралось достаточно.",
                     systemImage: "checkmark.seal")
        } else {
            TGCard {
                TGSectionHeader(title: "что чинить",
                                subtitle: "ранжировано по тому, сколько раз это случилось")
                ForEach(report.frictions) { item in
                    VStack(alignment: .leading, spacing: Token.Space.s4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title).textStyle(AppFont.bodyEmphasis)
                            Spacer(minLength: Token.Space.s8)
                            Text("\(item.count)")
                                .textStyle(AppFont.numeric(15, weight: .semibold)
                                    .color(Token.Status.overdueText))
                        }
                        Text(item.detail).textStyle(AppFont.caption).wraps()
                        if !item.screens.isEmpty {
                            Text("где: " + item.screens.joined(separator: ", "))
                                .textStyle(AppFont.micro)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if item.id != report.frictions.last?.id { TGDivider() }
                }
            }
        }
    }

    // MARK: Разрезы

    private var topActions: some View {
        TGCard {
            TGSectionHeader(title: "чаще всего")
            CountList(items: Array(report.byAction.prefix(10)))
        }
    }

    @ViewBuilder
    private var recordKinds: some View {
        if !report.byRecordKind.isEmpty {
            TGCard {
                TGSectionHeader(title: "что записывали")
                CountList(items: Array(report.byRecordKind.prefix(12)))
            }
        }
    }

    private var screens: some View {
        TGCard {
            TGSectionHeader(title: "экраны")
            CountList(items: Array(report.byScreen.prefix(15)))
            if !report.untouchedScreens.isEmpty {
                TGDivider()
                Text("не открывали ни разу").textStyle(AppFont.micro)
                Text(report.untouchedScreens.joined(separator: ", "))
                    .textStyle(AppFont.caption)
                    .wraps()
                TGExplainer(text: "Раздел, в который не зашли за две недели, — это либо лишний раздел, либо его не нашли. Второе чинится, первое убирается.")
            }
        }
    }

    @ViewBuilder
    private var days: some View {
        if report.byDay.count > 1 {
            TGCard {
                TGSectionHeader(title: "по дням")
                CountList(items: report.byDay)
            }
        }
    }

    // MARK: Сеансы

    private var sessions: some View {
        TGCard {
            TGSectionHeader(title: "сеансы",
                            subtitle: "новый начинается после четверти часа молчания")
            ForEach(report.sessions.reversed().prefix(20)) { session in
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    Button {
                        expanded = expanded == session.id ? nil : session.id
                        Haptics.tap()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                            Text("\(Fmt.shortDay(session.startedAt)) · \(Fmt.clock(session.startedAt))")
                                .textStyle(AppFont.bodyEmphasis)
                            Spacer(minLength: Token.Space.s8)
                            Text(sessionValue(session)).textStyle(AppFont.micro)
                            Image(systemName: expanded == session.id ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Token.Ink.faint)
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expanded == session.id {
                        ForEach(Array(steps(of: session.id).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .textStyle(AppFont.numeric(12, weight: .regular))
                                .wraps()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(session.screens.prefix(6).joined(separator: " → "))
                            .textStyle(AppFont.caption)
                            .wraps()
                    }
                }
                if session.id != report.sessions.reversed().prefix(20).last?.id { TGDivider() }
            }
        }
    }

    private func sessionValue(_ session: UsageReport.Session) -> String {
        var parts = ["\(session.actions) действий"]
        if session.records > 0 { parts.append("\(session.records) записей") }
        if session.length >= 60 { parts.append(Fmt.duration(session.length)) }
        return parts.joined(separator: " · ")
    }

    /// Строки одного сеанса: то самое «что было сделано» по шагам.
    private func steps(of session: String) -> [String] {
        entries.filter { $0.session == session }.map { entry in
            var line = "\(Fmt.clock(entry.at))  \(UsageReport.screenTitle(entry.screen)) · "
            line += entry.kind?.title ?? entry.action
            if let detail = entry.detail { line += " · \(detail)" }
            if entry.result != .done { line += " · \(entry.result.title)" }
            return line
        }
    }

    // MARK: Ручки

    private var controls: some View {
        TGCard {
            TGSectionHeader(title: "журнал")
            Toggle("Вести журнал действий", isOn: Binding(
                get: { isOn },
                set: { isOn = $0; UsageLog.isOn = $0 }
            ))
            .textStyle(AppFont.body)
            TGDivider()
            ShareLink(
                item: TextFile(name: "togo-otchet.txt", text: report.text),
                preview: SharePreview("Того · отчёт о действиях")
            ) {
                TGListRow(title: "Отчёт словами · txt", systemImage: "square.and.arrow.up")
            }
            .disabled(report.isEmpty)
            TGDivider()
            ShareLink(
                item: TextFile(name: UsageLog.fileName, text: raw),
                preview: SharePreview("Того · журнал действий")
            ) {
                TGListRow(title: "Весь журнал · строка на действие", systemImage: "doc.text")
            }
            .disabled(report.isEmpty)
            TGDivider()
            TGButton(title: "Очистить журнал", variant: .destructive,
                     size: .medium, systemImage: "trash") {
                isConfirmingClear = true
            }
            .disabled(report.isEmpty)
        }
    }

    private var privacy: some View {
        TGCard {
            TGSectionHeader(title: "что в нём лежит")
            Text("Только имена действий: «записал · еда · сделано». Ни граммов, ни заметок, ни клички, ни имён — по журналу нельзя восстановить ни одной записи дневника.")
                .textStyle(AppFont.caption)
            Text("Файл лежит в папке приложения на этом телефоне и никуда не уходит. Старше \(Fmt.days(Int(UsageLog.keepDays))) не хранится.")
                .textStyle(AppFont.caption)
        }
    }
}

/// Список «сколько раз» с полоской: цифру читают глазами, а полоску —
/// боковым зрением, и порядок величин виден без сравнения чисел.
private struct CountList: View {
    let items: [UsageReport.Count]

    private var peak: Int { max(1, items.map(\.count).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(item.name).textStyle(AppFont.caption).wraps()
                        Spacer(minLength: Token.Space.s8)
                        Text("\(item.count)").textStyle(AppFont.numeric(13, weight: .medium))
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Token.Action.primaryQuiet)
                            .frame(width: max(2, geometry.size.width * fraction(item.count)))
                    }
                    .frame(height: 4)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func fraction(_ count: Int) -> Double {
        min(1, Double(count) / Double(peak))
    }
}

/// Обёртка, чтобы отдать обычный текст в системный «Поделиться».
nonisolated struct TextFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            SentTransferredFile(try Exporter.writeTemporary(file.text, named: file.name))
        }
    }
}
