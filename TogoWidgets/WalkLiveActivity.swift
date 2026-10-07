import WidgetKit
import SwiftUI
import ActivityKit

/// Идущий выход на локскрине: секунды идут у всех, кто в семье.
///
/// Отсюда можно отметить, что собака сделала, — не разблокируя телефон
/// и не открывая приложение. Ради этого живая активность и нужна:
/// на улице телефон лежит в кармане, а отметить надо здесь и сейчас.
///
/// Заканчивать прогулку отсюда нельзя: итог спрашивается один раз
/// и только в приложении, когда человек уже вернулся и остановился.
///
/// **Виды уехали в `TogoShared/LiveActivity/WalkActivityView.swift`
/// 07.10.2026, и обёртка оставлена пустой нарочно.** Пока карточка
/// принимала `ActivityViewContext`, построить её вне живой активности
/// было нельзя ничем — ни тестом, ни превью, ни галереей, — и
/// единственная поверхность продукта, которую человек видит
/// с заблокированного экрана на улице, оставалась **непроверяемой**,
/// а не непроверенной.
///
/// Всё, что здесь есть, — превращение контекста в значения. Появится
/// в этом файле логика или хоть одна подпись — вернётся
/// и непроверяемость; то же условие записано у обёртки виджета
/// (`TodayWidgetEntry`) и по той же причине.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            WalkActivityView(dogName: context.attributes.dogName,
                             startedBy: context.attributes.startedBy,
                             startedAt: context.state.startedAt,
                             tally: context.state.tally)
                .activityBackgroundTint(Token.Surface.card)
                .activitySystemActionForegroundColor(Token.Ink.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WalkIslandView.Leading(dogName: context.attributes.dogName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WalkIslandView.Trailing(startedAt: context.state.startedAt)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WalkIslandView.Bottom(startedBy: context.attributes.startedBy,
                                          dogName: context.attributes.dogName,
                                          tally: context.state.tally)
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .frame(maxWidth: 44)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }
}
