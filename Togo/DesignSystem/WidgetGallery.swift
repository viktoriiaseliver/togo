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
            датаПоМесяцам
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

    /// Та же строка на все двенадцать месяцев, день 17.
    ///
    /// **Худший месяц не угадывается, а показывается.** Первая редакция
    /// брала «17 янв.» как «длинную дату» — рассуждением. Переводчица
    /// померила: худший случай у каждого языка свой — `ru` «17 февр.»,
    /// `fr` «17 janv.», `uk` «17 квіт.», все по восемь знаков, а `en_US`
    /// одинаков всегда, потому что сокращения там трёхбуквенные.
    ///
    /// Угадывать пришлось бы заново на каждом языке, и один раз я уже
    /// угадал мимо: украинский был снят на «9 вер.» (шесть знаков)
    /// при худшем восемь — то есть считался проверенным, не будучи им.
    ///
    /// И причина промаха общая: `сейчас` в галерее — сентябрьское,
    /// поэтому и он, и переводчица мерили сентябрём. **Месяц в фикстуре
    /// — тоже допущение, и выбрано оно не нами, а календарём.**
    /// Двенадцать строк дешевле одного такого допущения.
    ///
    /// Печатается только `sinceText` — та самая функция, что и во вью.
    /// Дублируется не логика, а кегль и ширина: ради того, чтобы
    /// двенадцать строк поместились на один кадр.
    private var датаПоМесяцам: some View {
        group("Дата: все двенадцать месяцев, день 17") {
            TGExplainer(text: "Сокращения месяцев разной длины, и у каждого языка свой худший месяц. Дата стоит в голове строки — значит она решает, что уцелеет при обрезке.")
            ForEach(1...12, id: \.self) { месяц in
                рамка(ширина: 170, высота: 22) {
                    Text(SnapshotText.sinceText(тишина(месяц: месяц)))
                        .font(.caption)
                        .foregroundStyle(Token.Ink.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    /// Снимок тишины с датой «17-е число такого-то месяца».
    private func тишина(месяц: Int) -> WidgetSnapshot {
        var s = тишина
        var части = DateComponents()
        части.year = 2025
        части.month = месяц
        части.day = 17
        части.hour = 9
        s.urineSilenceSince = Calendar(identifier: .gregorian).date(from: части)
            ?? Self.сейчас
        return s
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
            TGExplainer(text: "Настоящая ширина слота принадлежит системе и здесь НЕ воспроизведена. Лестница отвечает на вопрос «что короче» и не отвечает на вопрос «влезет ли на локскране».")
            TGExplainer(text: "Две клички нарочно. Кличка — переменная часть строки, и бюджет, померенный коротким именем, есть не у всех собак.")
            лестница(кличка: "Стич")
            лестница(кличка: "Белладонна")
        }
    }

    /// Одна кличка — пять ширин.
    ///
    /// Смотреть надо **две** ступени, а не одну: где строка встаёт
    /// целиком и где она обрезана, но смысл ещё цел. Вторая важнее —
    /// выбор идёт не между «влезет» и «не влезет», а между тем,
    /// что увидит тот, у кого не влезло.
    private func лестница(кличка: String) -> some View {
        var снимок = тишина
        снимок.dogName = кличка
        return VStack(alignment: .leading, spacing: Token.Space.s8) {
            подпись("кличка «\(кличка)» · \(кличка.count) знаков")
            ForEach([110, 130, 150, 170, 190], id: \.self) { ширина in
                HStack(spacing: Token.Space.s12) {
                    Text("\(ширина)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Token.Ink.secondary)
                        .monospacedDigit()
                    рамка(ширина: CGFloat(ширина), высота: 22) {
                        TodayWidgetView(snapshot: снимок, family: .accessoryInline,
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
