import SwiftUI
import UIKit
import SwiftData
import PhotosUI

/// Пописал дома — отметка без прогулки.
///
/// **Решение Виктории 27.10.2026: «с дома отметка туалет, покакал».**
/// «Покакал» у нас был всегда (`StoolSheet`), а «пописал» — только
/// на прогулке: кнопкой на экране «На улице» и на блокировке.
/// Дома отметить его было нечем, хотя щенок и больная собака ходят
/// именно дома, и для врача это та же величина.
///
/// # Почему отдельная шторка, а не кнопка в «Записать»
///
/// У мочи есть вопрос, которого нет у прогулочной отметки: **лужа это
/// или попросился**. На улице он не стоит — там всё в траву. Дома
/// разница медицинская: лужа у приученной собаки — это инцидент
/// (`IncidentKind.puddle`), а попросился и вывели — обычный выход.
///
/// Спрашивается одним рядом из двух кнопок, без «Сохранить»: запись
/// уходит сразу, как у стула. Человек с тряпкой в руке не заполняет
/// форму.
///
/// > **Чего здесь НЕТ намеренно: времени.** Запись встаёт «сейчас»,
/// > как все быстрые. Сдвинуть время можно правкой записи в ленте —
/// > тот же путь, что у остальных, и второго входа он не заводит.
struct UrineAtHomeSheet: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        TGSheet(title: "Туалет дома", subtitle: .готовая(Fmt.clock(Date()))) {
            TGExplainer(text: "Отмечаем, что было дома. На прогулке это отмечается кнопками на экране «На улице».")

            TGCard(spacing: Token.Space.s8) {
                кнопка(title: "Попросился и вывели",
                       detail: "обычный выход, просто записали дома",
                       symbol: "drop",
                       тон: Token.Ink.primary) { записать(лужа: false) }

                кнопка(title: "Лужа дома",
                       detail: "уходит в инциденты — врач спросит именно про них",
                       symbol: "exclamationmark.triangle",
                       тон: Token.Status.overdueText) { записать(лужа: true) }
            }
        }
        .presentationDetents([.medium])
    }

    private func кнопка(title: LocalizedStringKey,
                        detail: LocalizedStringKey,
                        symbol: String,
                        тон: Color,
                        действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            TGIconRow(symbol: symbol, title: title, detail: detail)
                .foregroundStyle(тон)
                // Нижняя граница цели касания, не «покрупнее»: у шторки,
                // которую открывают с тряпкой в руке, промах стоит
                // второго захода.
                .frame(minHeight: Token.Size.tapTarget)
        }
        .buttonStyle(.plain)
    }

    /// Лужа — это ИНЦИДЕНТ, а не выход, и это не придирка к слову.
    ///
    /// `LogKind.incident` уезжает в сводку врачу и считается порогом
    /// тревоги; `LogKind.outing` — обычная запись дня. Записать лужу
    /// выходом значило бы спрятать её от врача ровно там, где она
    /// и нужна.
    private func записать(лужа: Bool) {
        guard let dog else { dismiss(); return }
        let log = EventLog(context: context, appState: appState)
        if лужа {
            log.record(.incident, dog: dog,
                       confirmation: String(localized: "Записано · лужа дома")) { event in
                event.incidentKindRaw = IncidentKind.puddle.rawValue
            }
        } else {
            log.record(.outing, dog: dog,
                       confirmation: String(localized: "Записано · пописал дома")) { event in
                event.outcomeRaw = OutingOutcome.urine.rawValue
            }
        }
        dismiss()
    }
}
