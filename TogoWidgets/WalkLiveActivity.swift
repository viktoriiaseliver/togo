import WidgetKit
import SwiftUI
import ActivityKit

/// Идущий выход на локскрине: секунды идут у всех, кто в семье.
/// Останавливать её из виджета нельзя — результат спрашивается один раз
/// и только в приложении.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Token.Surface.card)
                .activitySystemActionForegroundColor(Token.Ink.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.dogName, systemImage: "figure.walk")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("вывел \(context.attributes.startedBy)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    private func lockScreen(_ context: ActivityViewContext<WalkActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("выход идёт")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Token.Action.primary)
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Token.Ink.primary)
                Text("\(context.attributes.startedBy) вывела \(context.attributes.dogName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Ink.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "figure.walk.departure")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Token.Ink.silhouette)
        }
        .padding(14)
    }
}
