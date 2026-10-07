import SwiftUI
import SwiftData

/// Первый вход ситтера: пять строк вместо истории болезни.
///
/// Из хендофа (18c): еда, доза, прогулки, запреты, эскалация. Текст пишет
/// хозяйка при приглашении — здесь он только показывается. **Диагноза
/// на экране нет намеренно:** ситтеру он не нужен, а лишнее медицинское
/// в чужих руках — лишний риск.
struct SitterBriefingScreen: View {
    let dog: Dog?
    var ownerName: String?
    var until: Date?
    var onStart: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var lines: [(String, String, String)] {
        guard let dog else { return [] }
        return [
            ("fork.knife", "Еда", dog.sitterFood),
            ("pills", "Доза", dog.sitterDose),
            ("figure.walk", "Гулять", dog.sitterWalks),
            ("hand.raised", "Нельзя", dog.sitterForbidden),
            ("exclamationmark.bubble", "Если что", dog.sitterEscalation),
        ].filter { !$0.2.isEmpty }
    }

    var body: some View {
        TGScreen {
            TGCard {
                Text("Ты с \(dog.flatMap(\.nameIfAny) ?? String(localized: "собакой"))\(untilText)").textStyle(AppFont.cardTitle)
                if let ownerName {
                    Text("\(ownerName) открыла доступ\(rangeText)").textStyle(AppFont.caption)
                }
            }

            if lines.isEmpty {
                TGCard {
                    TGExplainer(text: "Хозяйка пока не написала инструкцию. Спроси её — или отмечай как есть: приложение подскажет по режиму дня.")
                }
            } else {
                TGCard(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index > 0 { TGDivider() }
                        TGIconRow(symbol: line.0, title: .готовая(line.1), detail: .готовая(line.2))
                            .padding(.vertical, Token.Space.s10)
                    }
                }
            }

            TGExplainer(text: "Это всё, что нужно знать. Диагнозов и истории болезни здесь нет — они хозяйке, не тебе.")
        }
        .navigationTitle("Инструкция")
        .posterHeader("Инструкция")
        .usageScreen(.sitter)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            TGButton(title: "Понятно, открыть «Сегодня»") {
                onStart?()
                dismiss()
            }
            .padding(Token.Spacing.screenPadding)
        }
    }

    private var untilText: String {
        guard let until else { return "" }
        return String(localized: " до \(Fmt.shortDay(until))")
    }

    private var rangeText: String {
        guard let until else { return "" }
        return " · \(Fmt.shortDay(Date())) — \(Fmt.shortDay(until))"
    }
}

/// Хозяйка пишет инструкцию один раз.
struct SitterBriefingEditor: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGSheet(title: "Инструкция ситтеру",
                subtitle: "пять строк, которые он прочтёт за минуту") {
            if let dog {
                field("Еда", placeholder: "120 г сухого из банки на кухне · 8:00 и 19:00. Ничего со стола.",
                      text: Binding(get: { dog.sitterFood }, set: { dog.sitterFood = $0 }))
                field("Доза", placeholder: "1 таблетка из жёлтой коробки, спрятать в сыр · утром с едой.",
                      text: Binding(get: { dog.sitterDose }, set: { dog.sitterDose = $0 }))
                field("Гулять", placeholder: "3 раза, не меньше 20 минут. С другими собаками — можно.",
                      text: Binding(get: { dog.sitterWalks }, set: { dog.sitterWalks = $0 }))
                field("Нельзя", placeholder: "Курица, кости, лакомства с рынка. Не спускать с поводка у дороги.",
                      text: Binding(get: { dog.sitterForbidden }, set: { dog.sitterForbidden = $0 }))
                field("Если что", placeholder: "Рвота или отказ от еды — запиши здесь и напиши мне.",
                      text: Binding(get: { dog.sitterEscalation }, set: { dog.sitterEscalation = $0 }))

                TGExplainer(text: "Диагноз сюда писать не надо: ситтеру он не поможет, а на чужом экране ему не место.")
            }
        } footer: {
            TGButton(title: "Сохранить") {
                guard context.persist(otherwise: {}) else {
                    Haptics.warning()
                    return
                }
                Haptics.success()
                dismiss()
            }
        }
        .presentationDetents([.large])
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        TGCard {
            TGSectionHeader(title: .готовая(title.lowercased()))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...5)
                .textStyle(AppFont.body)
        }
    }
}
