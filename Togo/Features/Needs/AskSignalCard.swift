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

    private var weekAgo: Date { now.addingTimeInterval(-7 * 24 * 3600) }
    private var twoWeeksAgo: Date { now.addingTimeInterval(-14 * 24 * 3600) }

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
                .foregroundStyle(isDisplacing ? Token.Status.waitingText : Token.Action.done)
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
                HStack(spacing: 2) {
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
            Text("Не открывать дверь в момент лая — подождать одну-две секунды тишины и открыть тогда. Открывается дверь после тишины — закрепляется тишина. Ругать не нужно: лай не проступок, это то, что работало.")
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
