#if DEBUG
import SwiftUI

/// Галерея плаката: единственное место, где его пять режимов можно
/// **увидеть** рядом.
///
/// **Заведена 07.10.2026 вместе с самим плакатом, и это не удобство,
/// а условие приёмки.** `PosterMode` был написан, покрыт восемью
/// тестами и не вызывался ниоткуда; подключая его к экрану, я получил
/// бы поверхность, у которой пять состояний и ни одного способа
/// посмотреть на четыре из них: «Сегодня» показывает ровно то, что
/// сегодня, а тревогу и час дозы на экране ещё надо устроить.
///
/// > **Прежде чем проверять поверхность, проверь, что её МОЖНО
/// > проверить.** Поверхность без кадра — не «непроверенная», а
/// > «непроверяемая», и первое лечится взглядом, второе только
/// > переделкой входа.
///
/// Поэтому `TGPoster` принимает значения, а не стор: собрать его можно
/// из теста, из превью и отсюда. Тот же приём, которым 07.10 сделали
/// снимаемой карточку живой активности.
///
/// **Чего эта галерея НЕ доказывает.** Что экран соберёт плакат верно:
/// режим на живом экране считает `PosterMode.mode(_:)` из состояния
/// дня, и ошибка в том, ЧТО передали, здесь не видна. Галерея отвечает
/// «как выглядит режим», а не «тот ли режим показали».
struct PosterGallery: View {

    /// Час фиксирован: кадр, который нельзя повторить, нельзя и сравнить.
    private static let сейчас = Date(timeIntervalSince1970: 1_759_000_000)

    var body: some View {
        TGScreen(title: "Плакат") {
            TGExplainer(text: "Пять режимов плаката. Цвет блока выбирает PosterMode по состоянию дня — здесь режим передан значением, поэтому кадр повторяется. Доза — единственный режим с инверсной подписью.")

            режим(.usual, подпись: "обычный день",
                  caption: .init(symbol: "figure.walk", text: "на улице были"),
                  reading: .hoursMinutes(h: 3, m: 20),
                  next: .init(symbol: "fork.knife", what: "корм", when: "в 18:00"),
                  progress: 0.4)

            режим(.fasting, подпись: "натощак · янтарь",
                  caption: .init(symbol: "clock.badge.exclamationmark", text: "не кормить до 21:00"),
                  reading: .hoursMinutes(h: 1, m: 5),
                  next: .init(symbol: "pills", what: "таблетка", when: "в 21:00"),
                  progress: 0.75)

            // Доза — единственный режим, где подпись инверсная. Если
            // на кадре она окажется того же цвета, что на остальных
            // четырёх, значит `needsInverseLabel` не доехал до вида.
            режим(.dose, подпись: "час дозы · инверсная подпись",
                  caption: .init(symbol: "pills.fill", text: "пора дать таблетку"),
                  reading: .hoursMinutes(h: 0, m: 0),
                  next: .init(symbol: "checkmark", what: "отметить", when: "сейчас"),
                  progress: 1)

            режим(.alarm, подпись: "тревога · терракот",
                  caption: .init(symbol: "exclamationmark.triangle.fill", text: "кровь в стуле"),
                  reading: .hoursMinutes(h: 0, m: 40),
                  next: .init(symbol: "phone.fill", what: "позвонить врачу", when: "сейчас"),
                  progress: nil)

            // Ночь: подписи статусным цветом здесь быть не должно —
            // `carriesStatusColour` у этого режима ложно. Подпись
            // ПЕРЕДАНА нарочно: если она появится на кадре, значит вид
            // спрашивает не у режима, а у себя.
            режим(.quiet, подпись: "ночь · нейтральный, подпись передана и НЕ должна появиться",
                  caption: .init(symbol: "moon.fill", text: "ЭТОЙ СТРОКИ НА КАДРЕ БЫТЬ НЕ ДОЛЖНО"),
                  reading: .sentence("Сегодня ещё не выходили"),
                  next: nil,
                  progress: nil)

            group("Сжатый блок · при прокрутке") {
                TGPoster(mode: .usual,
                         reading: .hoursMinutes(h: 3, m: 20),
                         caption: .init(symbol: "figure.walk", text: "на улице были"),
                         next: .init(symbol: "fork.knife", what: "корм", when: "в 18:00"),
                         progress: 0.4,
                         collapsed: true)
            }

            // Узкая ширина — не косметика: показание 112 pt взято
            // из макета для 402, а оси устройства в токенах нет вовсе.
            // Здесь видно, что число ужимается, а не рвётся.
            group("Показание на ширине SE · 375") {
                TGPoster(mode: .usual,
                         reading: .hoursMinutes(h: 14, m: 15),
                         caption: .init(symbol: "figure.walk", text: "на улице были"),
                         next: .init(symbol: "fork.knife", what: "корм", when: "в 18:00"),
                         progress: 0.4)
                    .frame(width: 375)
            }

            // Двузначные часы и минуты разом — самая широкая строка,
            // какая бывает. «14 ч 15 мин» героем уже рвалось посередине
            // числа кадром 24.09; у плаката числа отдельные, и проверить
            // надо именно это.
            group("Самое широкое показание") {
                TGPoster(mode: .fasting,
                         reading: .hoursMinutes(h: 23, m: 59),
                         caption: .init(symbol: "clock", text: "не кормить"),
                         next: nil,
                         progress: 0.5)
            }
        }
    }

    private func режим(_ mode: PosterMode,
                       подпись: String,
                       caption: TGPoster<EmptyView>.Caption,
                       reading: TGPoster<EmptyView>.Reading,
                       next: TGPoster<EmptyView>.Next?,
                       progress: Double?) -> some View {
        group(подпись) {
            TGPoster(mode: mode,
                     reading: reading,
                     caption: caption,
                     next: next,
                     progress: progress)
                // Опознаётся приёмкой по режиму, а не по подписи:
                // подпись — текст на русском, и на французском прогоне
                // тест искал бы строку, которой нет. `rawValue` —
                // единственное, что у режима не переводится.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("плакат-\(mode.rawValue)")
        }
    }

    private func group<Content: View>(_ заголовок: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            Text(.готовая("режим · \(заголовок)"))
                .textStyle(AppFont.caption)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
