import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// Идущий выход на локскрине: секунды идут у всех, кто в семье.
///
/// Отсюда можно отметить, что собака сделала, — не разблокируя телефон
/// и не открывая приложение. Ради этого живая активность и нужна:
/// на улице телефон лежит в кармане, а отметить надо здесь и сейчас.
///
/// Заканчивать прогулку отсюда нельзя: итог спрашивается один раз
/// и только в приложении, когда человек уже вернулся и остановился.
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
                    VStack(spacing: 6) {
                        Text(context.state.tally ?? "вывел \(context.attributes.startedBy)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        markButtons
                    }
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
                Text(context.state.tally
                     ?? "\(context.attributes.startedBy) вывела \(context.attributes.dogName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            markButtons
        }
        .padding(14)
    }

    /// Две кнопки, обе крупные.
    ///
    /// Список короткий намеренно: на морозе одной рукой человек попадёт
    /// в две большие цели, а не в восемь маленьких. Всё остальное —
    /// в приложении, куда он всё равно заглянет, когда вернётся.
    private var markButtons: some View {
        HStack(spacing: 8) {
            markButton(.urine)
            markButton(.stool)
        }
    }

    private func markButton(_ kind: WalkMarkKind) -> some View {
        Button(intent: WalkMarkIntent(kind)) {
            VStack(spacing: 2) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(kind.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 56, height: 48)
        }
        .buttonStyle(.plain)
        .tint(Token.Action.primary)
        .accessibilityLabel("Отметить: \(kind.title)")
    }
}
