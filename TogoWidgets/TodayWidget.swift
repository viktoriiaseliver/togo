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
        .configurationDisplayName("Togo · просится")
        .description("Когда кормили и сколько он не писал — не открывая приложение.")
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
                Text(едаСтрокой).font(.caption2)
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
                Text(едаСтрокой)
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
        guard let seconds = snapshot.sinceUrineSeconds else {
            return String(localized: "записей пока нет")
        }
        return String(localized: "моча \(Fmt.duration(seconds)) назад")
    }

    /// Еда — первой строкой после вердикта, потому что ради неё
    /// приложение и открывают. Порядок: сколько прошло, потом сколько
    /// из скольких — «2 из 2» отвечает на вопрос «уже кормили?»,
    /// а «3 ч назад» на вопрос «пора ли».
    private var едаСтрокой: String {
        guard let last = snapshot.lastMealAt else {
            return snapshot.mealsPlanned > 0
                ? String(localized: "ещё не ели")
                : String(localized: "еды пока нет")
        }
        let прошло = Fmt.duration(Date().timeIntervalSince(last))
        guard snapshot.mealsPlanned > 0 else {
            return String(localized: "ел \(прошло) назад")
        }
        return String(localized: "ел \(прошло) назад · \(snapshot.mealsToday) из \(snapshot.mealsPlanned)")
    }

    private var inlineText: String {
        guard let seconds = snapshot.sinceUrineSeconds else { return snapshot.dogName }
        return "\(snapshot.dogName) · \(Fmt.duration(seconds))"
    }
}
