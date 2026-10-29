import WidgetKit
import SwiftUI
import UIKit

/// Виджет локскрина и главного экрана: три скорости на один и тот же путь —
/// новичок идёт через кнопки в приложении, опытный смотрит сюда.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetEntry(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(for: .widget) {
                    WidgetBackdrop(photo: entry.photo)
                }
        }
        .configurationDisplayName("Togo · просится")
        .description("Когда кормили и сколько он не писал — не открывая приложение.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Фото фона — то же самое, что у экранов приложения.
    ///
    /// Читается **здесь**, при сборке ленты, а не в `body`: тело вида
    /// виджета рисуется системой когда угодно и сколько угодно раз,
    /// и чтение файла из него — это диск в каждом кадре. Заодно так
    /// фото попадает в заглушку, то есть в галерею выбора виджета.
    var photo: BackgroundPhoto?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .empty, photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now,
                                 snapshot: WidgetBridge.read(),
                                 photo: BackgroundBridge.photo(for: .widget)))
    }

    /// Лента на час вперёд, запись в минуту.
    ///
    /// **Здесь была одна запись и «перечитать через пятнадцать минут»,
    /// и число на плитке стояло.** Вид считал интервал от `Date()`
    /// в момент отрисовки, а рисует система ленту заранее: «2 ч 11 мин»
    /// держалось до следующего пересбора, то есть до четверти часа,
    /// а при разряженном бюджете виджета — дольше. Локскрин был хуже:
    /// он печатал `sinceUrineSeconds`, посчитанные приложением, и при
    /// закрытом приложении не двигался вовсе (замер 29.10.2026, отзыв
    /// «виджет замирает»).
    ///
    /// Теперь у каждой записи своё `date`, и вид считает от него —
    /// `TodayWidgetEntry` отдаёт его как `now`. Шестьдесят записей —
    /// это один запрос ленты, а не шестьдесят: бюджет перезагрузок
    /// тратят `reloadTimelines`, а не длина ленты. Минута, а не пять:
    /// `Fmt.hoursMinutes` печатает минуты, и число, отстающее на четыре,
    /// неверно, а не грубо.
    ///
    /// Снимок читается один раз на всю ленту: его пересобирает
    /// приложение после каждой записи (`WidgetRefresh`) и само просит
    /// систему перечитать ленту. Через час лента кончается
    /// (`.atEnd`) и собирается заново с тем, что лежит в снимке.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetBridge.read()
        let photo = BackgroundBridge.photo(for: .widget)
        // С начала текущей минуты: иначе каждая запись сдвинута на
        // секунды запроса, и минута на плитке меняется не тогда,
        // когда на часах.
        let начало = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<60).map { шаг in
            SnapshotEntry(date: начало.addingTimeInterval(Double(шаг) * 60),
                          snapshot: snapshot, photo: photo)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Подложка виджета: фото человека или обычный фон.
///
/// **Затемнение обязательно, и это не украшение.** Поверх фотографии
/// лежат белые чернила `Token.Ink.primary`; на светлом снимке — снеге,
/// песке, белой шерсти — они пропадают, и виджет становится пустым
/// прямоугольником. Проверяется это не на нашем фото, а на самом
/// светлом, какое человек может положить.
struct WidgetBackdrop: View {
    let photo: BackgroundPhoto?

    var body: some View {
        ZStack {
            Token.Surface.screen
            if let photo, let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                Token.Surface.scrim
            }
        }
        .accessibilityHidden(true)
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
    /// Момент записи ленты, а не `Date()` отрисовки: система рисует
    /// ленту заранее, и `Date()` в теле вида — это час подготовки,
    /// а не час показа.
    let now: Date

    var body: some View {
        TodayWidgetView(snapshot: snapshot, family: family, now: now)
    }
}
