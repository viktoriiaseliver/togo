import SwiftUI

/// Как он просит.
///
/// Самая обидная из мёртвых систем: приложение честно спрашивало «как
/// попросил» после выходов, складывало ответы — и не показывало из них
/// ничего. А это единственная запись, которая **меняет** поведение,
/// а не фиксирует его: дверь открывается, и то, что собака сделала перед
/// этим, закрепляется.
///
/// Карточка появляется только когда есть что сказать: пока сигналов мало,
/// молчит.
struct AskSignalCard: View {
    let events: [LogEvent]
    let dogName: String
    var now: Date = Date()

    private var thisWeek: Diary.SignalTally {
        Diary.signalTally(events, from: weekAgo, to: now)
    }

    private var lastWeek: Diary.SignalTally {
        Diary.signalTally(events, from: twoWeeksAgo, to: weekAgo)
    }

    /// Границы «эта неделя против прошлой» — календарём, а не секундами.
    ///
    /// Было `now.addingTimeInterval(-7 * 24 * 3600)`. Дважды в год обе
    /// границы уезжают на час: в сутках перевода не 24 часа, а 23 или 25.
    ///
    /// **Цена здесь низкая, и это названо, а не замазано.** Сравнение
    /// остаётся честным — обе границы едут одинаково, и неделя против
    /// недели сравнивается с неделей против недели. Портится край:
    /// просьба, случившаяся в тот самый час, попадает не в свою неделю,
    /// а подпись «\(thisWeek.total) просьб за неделю» в этот день считает
    /// 167 часов или 169. Форма при этом ровно та, которой в проекте
    /// уже дважды заплатили (`TogoShared/Domain/DayTime.swift:7`), и
    /// чинится она одной строкой — дешевле, чем объяснять следующему,
    /// почему здесь так можно, а в семи других местах было нельзя.
    private var weekAgo: Date { Self.назад(дней: 7, от: now) }
    private var twoWeeksAgo: Date { Self.назад(дней: 14, от: now) }

    /// Отказ календаря возвращает исходный момент, а не подставляет
    /// секунды: пустое окно даёт «просьб мало, молчу» — состояние,
    /// которое у этой карточки штатное, — а подставленная арифметика
    /// вернула бы ровно тот дефект, от которого тут защита.
    private static func назад(дней: Int, от момент: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -дней, to: момент) ?? момент
    }

    private var isDisplacing: Bool {
        Diary.barkingIsDisplacingCalm(events, now: now)
    }

    /// Показываем, только когда есть на что смотреть.
    var isWorthShowing: Bool { thisWeek.total >= 3 }

    var body: some View {
        if isWorthShowing {
            TGCard {
                header
                bars
                advice
            }
        }
    }

    private var header: some View {
        HStack(spacing: Token.Space.s10) {
            Image(systemName: isDisplacing ? "exclamationmark.bubble" : "checkmark.bubble")
                .font(.system(size: Token.Size.iconMd, weight: .medium))
                .foregroundStyle(isDisplacing ? Token.Status.waitingText : Token.Action.doneText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(isDisplacing ? "Лай вытесняет спокойный сигнал" : "Как он просит")
                    .textStyle(AppFont.cardTitle)
                Text("\(thisWeek.total) просьб за неделю")
                    .textStyle(AppFont.caption)
            }
            Spacer(minLength: 0)
        }
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            row(title: "эта неделя", tally: thisWeek)
            if lastWeek.total > 0 {
                row(title: "две недели назад", tally: lastWeek)
            }
        }
    }

    private func row(title: String, tally: Diary.SignalTally) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            HStack {
                Text(title).textStyle(AppFont.micro)
                Spacer()
                Text("спокойно \(tally.calm) · лай \(tally.barking)")
                    .textStyle(AppFont.micro)
            }
            GeometryReader { geometry in
                HStack(spacing: Token.Space.s2) {
                    let total = max(1, tally.total)
                    Rectangle()
                        .fill(Token.Action.done)
                        .frame(width: geometry.size.width * CGFloat(tally.calm) / CGFloat(total))
                    Rectangle()
                        .fill(Token.Status.waitingText)
                        .frame(width: geometry.size.width * CGFloat(tally.barking) / CGFloat(total))
                    Rectangle().fill(Token.Surface.hairline)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): спокойно \(tally.calm), лай \(tally.barking)")
        }
    }

    @ViewBuilder
    private var advice: some View {
        TGDivider()
        if isDisplacing {
            Text("Что делать")
                .textStyle(AppFont.bodyEmphasis)
            Text("Не открывать дверь в момент лая: подождать одну-две секунды тишины и открыть тогда. Дверь открылась после тишины — закрепилась тишина. Ругать не нужно: лай не проступок, а то, что работало.")
                .textStyle(AppFont.caption)
                .wraps()
            Text("Если лай не уходит за две недели или появился резко — это может быть не поведение, а дискомфорт. Тогда к врачу, а не к занятиям.")
                .textStyle(AppFont.caption)
                .wraps()
        } else if thisWeek.calm > thisWeek.barking {
            Text("\(dogName) чаще просит спокойно. Дверь открывается после тишины — тишина и закрепляется.")
                .textStyle(AppFont.caption)
                .wraps()
        } else {
            Text("Пока поровну. Смотреть надо не на отдельную неделю, а на то, куда идёт соотношение.")
                .textStyle(AppFont.caption)
                .wraps()
        }
    }
}
