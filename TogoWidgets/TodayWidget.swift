import WidgetKit
import SwiftUI

/// Виджет локскрина и главного экрана: три скорости на один и тот же путь —
/// новичок идёт через кнопки в приложении, опытный смотрит сюда.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetEntry(snapshot: entry.snapshot)
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

/// Единственное, что осталось в расширении от самого вида, — чтение среды.
///
/// Сам вид уехал в `TogoShared/Widgets/TodayWidgetView.swift` 05.10:
/// пока он читал `@Environment(\.widgetFamily)` сам, его нельзя было
/// построить нигде, кроме живого виджета, — а виджет рисует SpringBoard,
/// и `app.screenshot()` до него не достаёт. Поверхность была
/// **непроверяемой**, и лечится это входом, а не старанием.
///
/// Обёртка нарочно пустая: всё, что в ней есть, — превращение среды
/// в значение. Появится здесь логика — вернётся и непроверяемость.
struct TodayWidgetEntry: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        TodayWidgetView(snapshot: snapshot, family: family)
    }
}
