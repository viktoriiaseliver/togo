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
/// **Макет «Кино» с этим спорит** — вторая кнопка там белая «Домой»;
/// разбор и цена в обе стороны — в голове `WalkActivityView`,
/// решать Виктории.
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
///
/// **23.10.2026 условие сработало, и это его первый выстрел.**
/// Компактные части «острова» были написаны прямо здесь —
/// `Image(systemName:)` и `Text(_, style: .timer)` в трёх замыканиях.
/// Пока там стоял один значок, цена была нулевой; редизайн добавил
/// компактной пилюле **подпись** («На улице») и **цвет** (зелёный
/// выхода), то есть ровно то, что обёртке иметь запрещено. Они уехали
/// в `WalkIslandView.CompactLeading/CompactTrailing/Minimal`
/// и попали под кадр вместе с остальными.
///
/// > Условие было написано на будущее и дождалось своего случая.
/// > Поправка стоила десяти строк **потому**, что запрет стоял заранее.
struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            WalkActivityView(dogName: context.attributes.dogName,
                             startedBy: context.attributes.startedBy,
                             startedAt: context.state.startedAt,
                             tally: context.state.tally)
                // **`#000000`, а не карточный `#1C1C1E`** — замер пикселя
                // на эталоне `16.png` дал у карточки живой активности
                // чистый чёрный, и разметка пакета говорит то же
                // (`background:#000`). До 23.10 здесь стоял
                // `Surface.card`: это был цвет ПРЕЖНЕЙ темы, а не
                // решение про «остров».
                //
                // Остаётся просьбой, а не результатом: поверх системы
                // рисует своё, и кадр из отрисовщика про это не знает.
                .activityBackgroundTint(Token.Surface.screen)
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
                WalkIslandView.CompactLeading()
            } compactTrailing: {
                WalkIslandView.CompactTrailing(startedAt: context.state.startedAt)
            } minimal: {
                WalkIslandView.Minimal()
            }
        }
    }
}
