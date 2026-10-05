import SwiftUI
import WidgetKit

/// Вид виджета «сегодня» — вынесен из `TogoWidgets` 05.10.2026.
///
/// **Зачем переезд.** Виджет рисует SpringBoard, и `app.screenshot()`
/// до него не достаёт: три поверхности правила тишины (виджет,
/// «остров», лист вердикта) были закрыты сторожем только на уровне
/// строк. «Что человек УВИДИТ» не проверял никто, и не по недосмотру —
/// **смотреть было не на что**.
///
/// > Прежде чем проверять поверхность, проверь, что её МОЖНО проверить.
/// > Поверхность без кадра — не «непроверенная», а «непроверяемая»,
/// > и первое лечится взглядом, второе только переделкой входа.
///
/// Тот же ход, что у Timer с карточкой Live Activity и что 28.09
/// со строками `SnapshotText`: вместо системного контекста — обычные
/// значения, и вью попадает в галерею отладки, то есть под кадр.
///
/// **Семейство приходит значением, а не из среды.** `@Environment(\.widgetFamily)`
/// вне виджета не задать ничем надёжным, и вью, читающая его сама,
/// остаётся непроверяемой даже после переезда. Среду читает тонкая
/// обёртка на стороне `TogoWidgets`, здесь — обычный параметр.
///
/// **`now` тоже параметром.** Внутри стоял `Date()`, и строка про еду
/// меняла бы кадр каждый час: кадр, который нельзя повторить, нельзя
/// и сравнить.
struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var now: Date = Date()

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(SnapshotText.inlineText(snapshot))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.verdictTitle).font(.headline)
                Text(SnapshotText.sinceText(snapshot)).font(.caption)
                Text(SnapshotText.mealLine(snapshot, now: now)).font(.caption2)
            }
        default:
            прямоугольный
        }
    }

    private var прямоугольный: some View {
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
            Text(SnapshotText.sinceText(snapshot))
                .font(.system(size: 12))
                .foregroundStyle(Token.Ink.secondary)
            Text(SnapshotText.mealLine(snapshot, now: now))
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
            } else if let fasting = snapshot.fastingEndsAt, fasting > now {
                Label {
                    // Через `String(localized:)` и `Fmt.clock`, а не
                    // `Text(fasting, style: .time)`. Ключ получается тот же
                    // (`не кормить до %@`), переводы уже лежат — но путь
                    // в каталог теперь виден и сторожу, и человеку.
                    //
                    // Повод: при переезде в общий слой `LocalizationDebtTests`
                    // насчитал здесь непереведённую строку. Строка была
                    // переведена — SwiftUI локализует литерал `Text`
                    // сам, — но сторож этого не видит: он ищет
                    // `localized:`. Это ПЕРВАЯ вью в общем слое, и правило
                    // сторожа писалось, когда вьюшек тут не было вовсе.
                    Text(String(localized: "не кормить до \(Fmt.clock(fasting))"))
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Token.Status.waitingText)
            }
        }
    }
}
