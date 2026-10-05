import SwiftUI
import SwiftData

/// Итог смены и её передача.
///
/// Из хендофа (18e): «Вместо потока „Игорь отметил…“ ×6 — одно уведомление
/// в конце смены: что закрыто, что переходит. „Принять смену“ — явный акт:
/// незакрытое не повисает ничьим».
struct ShiftHandoverSheet: View {
    let summary: ShiftSummary
    /// Кому переходит открытое.
    var successor: String?
    var onAccept: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGSheet(title: "Смена \(summary.shift.person) закончилась",
                subtitle: "\(summary.shift.hours) · \(summary.headline)") {
            if !summary.done.isEmpty { doneCard }
            if summary.open.isEmpty { allClosedCard } else { openCard }
            TGExplainer(text: "«Принять смену» — явное действие, а не тишина: незакрытое не должно повиснуть ничьим.")
        } footer: {
            TGButton(title: summary.open.isEmpty ? "Принять смену" : "Принять смену и \(summary.open.count) дело",
                     systemImage: "hand.raised") {
                onAccept()
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var doneCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "закрыто · \(summary.done.count)")
            ForEach(summary.done) { item in
                HStack(spacing: Token.Space.s12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Token.Action.doneText)
                    Text(item.title).textStyle(AppFont.body)
                    Spacer(minLength: 0)
                    if let by = item.by {
                        Text(by).textStyle(AppFont.caption)
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
            }
        }
    }

    /// Два ключа, а не один с подстановкой.
    ///
    /// Было: `"переходит\(successor.map { " к \($0)" } ?? "") · \(count)"`.
    /// Предлог « к » склеивался обычной строкой ДО того, как
    /// `LocalizedStringKey` шёл в каталог, — то есть приезжал
    /// на экран русским при любом языке. Француз читал «passe к Marie»,
    /// украинец «переходить к Марії». Ключ в каталоге был, перевод
    /// у ключа был, и починить это переводом было нельзя: предлога
    /// в ключе нет, на его месте `%@`.
    ///
    /// Теперь предлог внутри ключа, и переводчик ставит его там, где
    /// требует язык: по-украински «до», по-французски «à».
    private var заголовокОткрытого: LocalizedStringKey {
        if let successor {
            "переходит к \(successor) · \(summary.open.count)"
        } else {
            "переходит · \(summary.open.count)"
        }
    }

    private var openCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: заголовокОткрытого)
            ForEach(summary.open) { item in
                HStack(spacing: Token.Space.s12) {
                    Image(systemName: "circle")
                        .foregroundStyle(Token.Status.waitingText)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(item.title).textStyle(AppFont.bodyEmphasis)
                        Text("до \(Fmt.clock(item.due))").textStyle(AppFont.caption)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Token.Size.tapTarget)
            }
        }
    }

    private var allClosedCard: some View {
        TGCard {
            TGBanner(tone: .done, title: "Всё закрыто",
                     subtitle: "За смену не осталось ни одного открытого дела.",
                     systemImage: "checkmark.seal")
        }
    }
}

/// Вопрос хозяйке прямо из записи.
///
/// Из хендофа (18d): «Ситтер не сочиняет сообщение — выбирает готовый
/// вопрос, контекст едет вложением». Сочинять текст в чужом доме, когда
/// собака не доела, — именно то, чего человек стесняется и потому молчит.
struct AskOwnerSheet: View {
    let event: LogEvent
    let ownerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    private var options: [String] {
        switch event.kind {
        case .meal:
            ["Докормить позже или убрать миску?", "Это для него нормально?"]
        case .incident:
            ["Это уже было раньше?", "Ехать к врачу или наблюдать?"]
        case .stool:
            ["Так и должно быть?", "Менять корм не надо?"]
        default:
            ["Это нормально?", "Что мне делать?"]
        }
    }

    /// Контекст едет вложением сам — переписывать его руками не надо.
    private var attachment: String {
        var parts = [event.kind.title]
        if let subtitle = event.subtitle { parts.append(subtitle) }
        parts.append(Fmt.clock(event.date))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        TGSheet(title: "Спросить \(ownerName)",
                subtitle: "запись прикрепится к вопросу сама") {
            TGCard {
                TGSectionHeader(title: "что прикрепится")
                Text(attachment).textStyle(AppFont.body)
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "вопрос")
                ForEach(options, id: \.self) { question in
                    ShareLink(item: "\(attachment)\n\n\(question)") {
                        TGListRow(title: .готовая(question), accessory: .none)
                    }
                    .buttonStyle(.plain)
                    TGDivider()
                }
                TextField("Свой вопрос…", text: $custom, axis: .vertical)
                    .lineLimit(1...3)
                    .textStyle(AppFont.body)
                    .frame(minHeight: Token.Size.tapTarget)
            }

            if !custom.trimmingCharacters(in: .whitespaces).isEmpty {
                ShareLink(item: "\(attachment)\n\n\(custom)") {
                    TGCard { TGListRow(title: "Отправить свой вопрос",
                                       systemImage: "paperplane", accessory: .none) }
                }
                .buttonStyle(.plain)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
