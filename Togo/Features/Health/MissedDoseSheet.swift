import SwiftUI

/// Пропущенная доза: три выхода, ни одного упрёка.
///
/// Из хендофа: «Без вины в тексте: не "вы забыли", а "что сделать
/// сейчас". Рекомендуемый выход подсвечен, но все три равнодоступны.»
///
/// Рекомендация берётся из расписания самого препарата, а не из головы
/// приложения: оно не назначает лечение и говорит об этом прямо.
struct MissedDoseSheet: View {
    let medication: Medication
    let missed: MissedDose
    let now: Date
    /// Дать сейчас — следующая сдвинется.
    var onGiveNow: () -> Void
    /// Пропустить — следующая по расписанию.
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGSheet(title: .готовая(String(localized: "\(title) доза пропущена")),
                subtitle: .готовая(
                    String(localized: "окно закрылось в \(Fmt.clock(missed.windowClosedAt))")
                    + String(localized: " · сейчас \(Fmt.clock(now))"))) {
            if let toNext = missed.timeToNext(from: now) {
                TGCard {
                    Text("До следующей дозы \(Fmt.gap(toNext)). Что делаем сейчас?")
                        .textStyle(AppFont.body).wraps()
                }
            }

            option(title: "Дать сейчас",
                   detail: shiftDetail,
                   isRecommended: true,
                   action: { onGiveNow(); dismiss() })

            option(title: "Пропустить эту",
                   detail: "Следующая — по расписанию. Без двойной дозы.",
                   isRecommended: false,
                   action: { onSkip(); dismiss() })

            askVet

            TGExplainer(text: "Что делать с пропуском, пишут в инструкции к препарату. Приложение только считает время — решение за тобой и врачом.")
        }
        .presentationDetents([.large])
    }

    private var title: String {
        let hour = Calendar.current.component(.hour, from: missed.scheduledAt)
        switch hour {
        case ..<12: return "Утренняя"
        case ..<17: return "Дневная"
        default: return "Вечерняя"
        }
    }

    private var shiftDetail: String {
        guard let shifted = missed.nextIfGivenNow, let interval = missed.intervalIfGivenNow else {
            return "Следующая — по расписанию: приём один в день."
        }
        return "Следующая сдвинется на \(Fmt.clock(shifted)) — интервал \(Fmt.gap(interval))."
    }

    private func option(title: String, detail: String,
                        isRecommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TGCard {
                HStack(spacing: Token.Space.s8) {
                    Text(title).textStyle(AppFont.cardTitle)
                    if isRecommended {
                        Text("обычно так")
                            .textStyle(AppFont.micro.color(Token.Status.doneText))
                            .padding(.horizontal, Token.Space.s8)
                            .padding(.vertical, 2)
                            .background(Token.Action.primaryQuiet, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Token.Ink.secondary)
                }
                Text(detail).textStyle(AppFont.caption).wraps()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Третий выход. Тоже кнопка, а не сноска: спросить врача — это
    /// нормальный ответ, а не признание поражения.
    private var askVet: some View {
        let text = "\(medication.name) \(medication.doseText): пропущена доза "
            + "\(Fmt.clock(missed.scheduledAt)), сейчас \(Fmt.clock(now)). Что делать?"
        return ShareLink(item: text) {
            TGCard {
                HStack(spacing: Token.Space.s8) {
                    Text("Спросить врача").textStyle(AppFont.cardTitle)
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Token.Ink.secondary)
                }
                Text("Готовое сообщение: название, доза и время пропуска.")
                    .textStyle(AppFont.caption).wraps()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
