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

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: Token.Size.iconMd, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Token.Space.s24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(title).textStyle(AppFont.bodyEmphasis)
                Text(detail).textStyle(AppFont.caption).wraps()
            }
            Spacer(minLength: 0)
        }
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
