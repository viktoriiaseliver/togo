import SwiftUI

/// Как часто собаку выводят на самом деле.
///
/// Появилась по простой просьбе: «хорошо бы видеть, как часто собаку
/// в среднем надо выгуливать исходя из прогулок с ним». Норм здесь нет
/// и быть не может — у щенка, взрослой и пожилой собаки они разные, —
/// а записи есть. Приложение показывает, что получается, и молчит о том,
/// хорошо это или плохо: решает человек.
struct WalkRhythmCard: View {
    let rhythm: WalkRhythm
    var compact: Bool = false

    var body: some View {
        if compact {
            if rhythm.isReliable {
                Text(summary)
                    .textStyle(AppFont.caption)
                    .wraps()
            }
        } else {
            TGCard {
                TGSectionHeader(title: "как часто гуляем",
                                subtitle: rhythm.isReliable ? "за две недели" : nil)
                if rhythm.isReliable {
                    stats
                    if !rhythm.usualTimes.isEmpty {
                        TGDivider()
                        Text("Обычно выходите в " + rhythm.usualTimes.map(Fmt.clock(minuteOfDay:))
                            .joined(separator: ", ") + ".")
                            .textStyle(AppFont.caption)
                            .wraps()
                    }
                    TGDivider()
                    TGExplainer(text: "Это не норма, а зеркало: сколько получается у тебя. Сравнивать стоит не с чужой собакой, а с собой месяц назад.")
                } else {
                    TGExplainer(text: "Нужно хотя бы \(Fmt.days(WalkRhythm.minimumDays)) с записями — пока их \(rhythm.days). Просто продолжай отмечать выходы.")
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            TGStat(value: Fmt.decimal(rhythm.outingsPerDay), caption: "раз в день", size: 20)
            TGStat(value: Fmt.gap(rhythm.averageIndoors), caption: "дома между", size: 20)
            TGStat(value: Fmt.gap(rhythm.longestIndoors), caption: "дольше всего", size: 20)
        }
    }

    private var summary: String {
        String(localized: "Обычно выходите \(Fmt.decimal(rhythm.outingsPerDay)) раза в день, дома между выходами ")
            + String(localized: "в среднем \(Fmt.gap(rhythm.averageIndoors)).")
    }
}
