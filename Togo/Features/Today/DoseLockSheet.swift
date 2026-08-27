import SwiftUI

/// Замок: доза уже отмечена.
///
/// Из прототипа v2: повторный тап по закрытой дозе открывает объяснение,
/// а не ставит вторую отметку. Защита от двойной дозы в приложении была
/// и раньше, но отвечала тостом — то есть говорила «нельзя» и исчезала
/// через пять секунд, не сказав ни кто дал, ни когда.
///
/// Здесь три ответа на три разных вопроса, которые человек в этот момент
/// и задаёт: **кто уже дал**, **что если это правда другая доза**
/// и **что если я ошиблась**.
struct DoseLockSheet: View {
    let title: String
    /// Кто отметил и во сколько.
    let markedBy: String
    let markedAt: Date
    /// Записать отдельной дозой — редкий, но настоящий случай.
    var onRecordSeparately: () -> Void
    /// Снять отметку: отметили не то.
    var onUndo: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TGSheet(title: "Уже отмечено", subtitle: title) {
            TGCard {
                TGIconRow(symbol: "checkmark.circle",
                          title: "\(markedBy) отметила в \(Fmt.clock(markedAt))",
                          detail: "Вторую отметку приложение не поставит: две дозы порознь — это не путаница в дневнике, а передозировка.")
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "если это не она")
                TGButton(title: "Другая доза? Записать отдельно",
                         variant: .secondary, size: .medium) {
                    onRecordSeparately()
                    dismiss()
                }
                TGExplainer(text: "Отдельная запись со своим временем. Первая останется на месте.")
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "если ошиблись")
                TGButton(title: "Снять отметку", variant: .destructive, size: .medium,
                         systemImage: "arrow.uturn.backward") {
                    onUndo()
                    dismiss()
                }
                TGExplainer(text: "Доза вернётся в план дня, окно натощак пересчитается.")
            }
        }
        .presentationDetents([.medium])
    }
}
