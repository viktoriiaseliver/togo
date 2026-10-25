import SwiftUI
import Charts

/// Figma: `IconRow`. Иконка слева, заголовок и пояснение справа.
///
/// Этой строкой набраны списки возможностей на пейволле, потери при
/// понижении тарифа, «что нового» и карточки онбординга. Четыре копии
/// уже начали расходиться: в одной иконку скрыли от VoiceOver, в другой
/// нет, в третьей потерялся `Spacer` — и строка вела себя иначе при
/// длинном тексте.
struct TGIconRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    /// Иконка здесь всегда декоративная: смысл несёт заголовок рядом.
    var tint: Color = Token.Status.doneText

    /// Системный кегль. Читается, а не задаётся: сюда он приезжает
    /// от настройки **процесса**, и на этом же месте его подменяет
    /// аргумент запуска `-UIPreferredContentSizeCategoryName`.
    @Environment(\.dynamicTypeSize) private var размерТекста

    /// **Колонка значка не растёт с кеглем, а текст растёт** — и на
    /// доступных размерах она отнимает ширину у того, ради чего строка
    /// написана. Кадр 25.10.2026 (`до-правки/07-пейволл-ax5.png`,
    /// `AccessibilityXXXL`): «переключатель на вкладке собаки» вышло
    /// как «переключател / ь на вкладке собаки» — перенос ПОСРЕДИ
    /// слова, то есть слово перестало узнаваться.
    ///
    /// Перенос посреди слова SwiftUI делает только тогда, когда слово
    /// шире всей доступной строки. Значок с отступом держит
    /// `s24 + s12` = тридцать шесть точек при любой настройке,
    /// и ровно их не хватало: слово длиной в тринадцать букв
    /// на границу и выходило.
    ///
    /// На доступных размерах значок уходит НАД текстом, а текст
    /// получает всю ширину. Значок декоративный и скрыт от озвучки —
    /// его переезд ничего не меняет ни для VoiceOver, ни для порядка
    /// чтения. Раскладка выбирается явным `if`, а не `ViewThatFits`:
    /// тот в проекте запрещён.
    var body: some View {
        Group {
            if размерТекста.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Token.Space.s8) {
                    значок
                    текст
                }
            } else {
                HStack(alignment: .top, spacing: Token.Space.s12) {
                    значок
                    текст
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var значок: some View {
        Image(systemName: symbol)
            .font(.system(size: Token.Size.iconMd, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Token.Space.s24)
            .accessibilityHidden(true)
    }

    /// Дети у обеих раскладок — одни и те же. Разойдись они, и ветка,
    /// которую реже видят, отстанет молча.
    private var текст: some View {
        VStack(alignment: .leading, spacing: Token.Space.s2) {
            Text(title).textStyle(AppFont.bodyEmphasis).wraps()
            Text(detail).textStyle(AppFont.caption).wraps()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Оси графиков: тонкая сетка и подписи цветом подсказки.
    ///
    /// Одна и та же разметка была продублирована в питании и в истории.
    /// Если оси разъезжаются по стилю, два графика перестают читаться
    /// как один язык.
    func tgChartAxes(xStrideDays: Int = 7) -> some View {
        chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Token.Surface.hairline)
                AxisValueLabel().foregroundStyle(Token.Ink.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xStrideDays)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Token.Ink.secondary)
            }
        }
    }
}
