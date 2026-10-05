#if DEBUG
import SwiftUI
import WidgetKit

/// Галерея виджета: единственное место, где его строки можно **увидеть**.
///
/// **Заведена 05.10.2026, и до неё этой поверхности не видел глазами
/// никто.** Виджет рисует SpringBoard, `app.screenshot()` до него
/// не достаёт, а `TodayWidgetView` читала семейство из среды и строилась
/// только внутри живого виджета. Сторож на строки был — поведенческий,
/// на `SnapshotText`; он отвечает «верно ли посчитано» и молчит
/// про «верно ли сказано».
///
/// Ступень тишины мочи здесь первой нарочно: ради неё галерея
/// и заводилась.
struct WidgetGallery: View {
    /// Час фиксирован: кадр, который нельзя повторить, нельзя и сравнить.
    private static let сейчас = Date(timeIntervalSince1970: 1_759_000_000)

    var body: some View {
        TGScreen(title: "Виджет") {
            TGExplainer(text: "Строки приходят из SnapshotText — те же, что на локскране. Семейство и час передаются значением, поэтому кадр повторяется.")

            group("Тишина · отметок мочи нет") {
                семейства(тишина)
            }
            инлайнПоШиринам
            group("Обычный день") {
                семейства(обычный)
            }
            group("Данных нет вовсе") {
                семейства(.empty)
            }
        }
    }

    // MARK: - Снимки

    /// Дневник забросили: мочи нет восемнадцать дней, выходов тоже.
    private var тишина: WidgetSnapshot {
        var s = WidgetSnapshot.empty
        s.dogName = "Стич"
        s.dogInitial = "С"
        s.verdictTitle = "Непонятно"
        s.verdictBadge = "отметок мочи нет"
        s.sinceUrineSeconds = 434 * 3600
        s.urineSilenceSince = Self.сейчас.addingTimeInterval(-434 * 3600)
        s.lastMealAt = Self.сейчас.addingTimeInterval(-437 * 3600)
        s.mealsPlanned = 2
        return s
    }

    private var обычный: WidgetSnapshot {
        var s = WidgetSnapshot.empty
        s.dogName = "Стич"
        s.dogInitial = "С"
        s.verdictTitle = "Скорее просится"
        s.verdictBadge = "дольше обычного"
        s.sinceUrineSeconds = 7 * 3600
        s.lastMealAt = Self.сейчас.addingTimeInterval(-3 * 3600)
        s.mealsToday = 1
        s.mealsPlanned = 2
        return s
    }

    // MARK: - Раскладка

    private func семейства(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s12) {
            подпись("accessoryInline · «остров» и локскран")
            рамка(ширина: 170, высота: 24) {
                TodayWidgetView(snapshot: snapshot, family: .accessoryInline,
                                now: Self.сейчас)
            }
            подпись("accessoryRectangular · локскран")
            рамка(ширина: 170, высота: 72) {
                TodayWidgetView(snapshot: snapshot, family: .accessoryRectangular,
                                now: Self.сейчас)
            }
            подпись("systemSmall · главный экран")
            рамка(ширина: 158, высота: 158) {
                TodayWidgetView(snapshot: snapshot, family: .systemSmall,
                                now: Self.сейчас)
            }
        }
    }

    /// Инлайн при разных ширинах — и это **главное в галерее**.
    ///
    /// Вопрос переводчицы был не «влезает ли», а «какой из двух
    /// украинских вариантов влезает»: `немає позначок` взят вместо
    /// более точного `нічого не позначали` по длине, и до сегодня
    /// это решение не проверялось ничем, кроме счёта знаков.
    ///
    /// Поэтому здесь не один слот, а лестница ширин с подписями:
    /// видно **при какой ширине строка обрезается**, а не «поместилась
    /// на моём экране».
    private var инлайнПоШиринам: some View {
        group("Инлайн: при какой ширине обрезается") {
            TGExplainer(text: "Настоящая ширина слота принадлежит системе и здесь НЕ воспроизведена. Эта лестница отвечает на вопрос «что короче» и не отвечает на вопрос «влезет ли на локскране».")
            ForEach([110, 130, 150, 170, 190], id: \.self) { ширина in
                HStack(spacing: Token.Space.s12) {
                    Text("\(ширина)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Token.Ink.secondary)
                        .monospacedDigit()
                    рамка(ширина: CGFloat(ширина), высота: 22) {
                        TodayWidgetView(snapshot: тишина, family: .accessoryInline,
                                        now: Self.сейчас)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }

    private func рамка<Содержимое: View>(ширина: CGFloat, высота: CGFloat,
                                         @ViewBuilder _ содержимое: () -> Содержимое) -> some View {
        содержимое()
            .padding(8)
            .frame(width: ширина, height: высота, alignment: .leading)
            .background(Token.Surface.card,
                        in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous)
                    .strokeBorder(Token.Ink.silhouette.opacity(0.25), lineWidth: 1)
            )
    }

    private func подпись(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(Token.Ink.secondary)
    }

    private func group<Содержимое: View>(_ title: String,
                                         @ViewBuilder _ содержимое: () -> Содержимое) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s12) {
            TGSectionHeader(title: .готовая(title))
            содержимое()
        }
    }
}

#Preview {
    NavigationStack { WidgetGallery() }
}
#endif
