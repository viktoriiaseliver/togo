import WidgetKit
import SwiftUI

/// Виджет локскрина и главного экрана: три скорости на один и тот же путь —
/// новичок идёт через кнопки в приложении, опытный смотрит сюда.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(Token.Surface.screen, for: .widget)
        }
        .configurationDisplayName("Того · просится")
        .description("Сколько он не писал и что было утром — не открывая приложение.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetBridge.read()))
    }

    /// Обновляемся раз в пятнадцать минут: чаще незачем — интервалы у собаки
    /// измеряются часами.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetBridge.read())
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.verdictTitle).font(.headline)
                Text(sinceText).font(.caption)
                if let stool = snapshot.lastStoolSummary {
                    Text(stool).font(.caption2)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(snapshot.dogInitial)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Token.Action.done, in: Circle())
                    Text(snapshot.dogName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Token.Ink.primary)
                    Spacer(minLength: 0)
                }
                Text(snapshot.verdictTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Token.Ink.primary)
                Text(sinceText)
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Ink.secondary)
                Spacer(minLength: 0)
                if let started = snapshot.walkStartedAt {
                    Label {
                        Text(started, style: .timer)
                    } icon: {
                        Image(systemName: "figure.walk")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Token.Action.primary)
                } else if let fasting = snapshot.fastingEndsAt, fasting > .now {
                    Label {
                        Text("не кормить до \(fasting, style: .time)")
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Token.Status.waitingText)
                }
            }
        }
    }

    private var sinceText: String {
        guard let seconds = snapshot.sinceUrineSeconds else { return "записей пока нет" }
        return "моча \(Fmt.duration(seconds)) назад"
    }

    private var inlineText: String {
        guard let seconds = snapshot.sinceUrineSeconds else { return snapshot.dogName }
        return "\(snapshot.dogName) · \(Fmt.duration(seconds))"
    }
}
