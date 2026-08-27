import SwiftUI

/// Ответ на главный вопрос — один на экран, крупной цифрой.
///
/// Из редизайна по ресёрчу: «иерархия вместо ровного серого. Один герой
/// на экран крупной цифрой, всё остальное на два шага тише».
///
/// Вопрос у этого приложения один и тот же двадцать раз в день: давно ли
/// собака была на улице. Раньше ответ стоял мелкой строкой в шапке рядом
/// с весом — то есть ровно тем же кеглем, что и всё прочее, и глазу
/// не за что было зацепиться.
struct TodayHero: View {
    /// Сколько собака дома. Пусто — сегодня ещё не выходили.
    let indoors: TimeInterval?
    /// Идущий выход: пока он идёт, вопрос снят.
    let session: ActiveSession?
    let now: Date
    /// Как часто выходят обычно — вторая строка, тише.
    let rhythm: WalkRhythm
    let outingsToday: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s6) {
            headline
            if let support { Text(support).textStyle(AppFont.caption).wraps() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOver)
    }

    @ViewBuilder
    private var headline: some View {
        if let session {
            // Пока идёт выход, «давно ли гуляли» отвечает сам таймер.
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                TGStopwatch(session: session, now: now, style: AppFont.hero)
                Text(session.isPaused ? "на паузе" : "на улице")
                    .textStyle(AppFont.caption.color(Token.Status.doneText))
            }
        } else if let indoors {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(Fmt.hoursMinutes(indoors))
                    .textStyle(AppFont.hero)
                Text("назад")
                    .textStyle(AppFont.sectionTitle.color(Token.Ink.secondary))
            }
            Text("на улице были").textStyle(AppFont.caption)
        } else {
            Text("Сегодня ещё не выходили").textStyle(AppFont.sectionTitle)
        }
    }

    /// Строка про режим. Появляется, только когда есть с чем сравнивать:
    /// «обычно чаще» по двум дням — это не наблюдение, а шум.
    private var support: String? {
        guard session == nil, rhythm.isReliable else { return nil }
        let usual = Int(rhythm.outingsPerDay.rounded())
        guard usual > 0 else { return nil }

        if outingsToday < usual {
            return "Обычно выходите чаще · \(outingsToday) "
                + "\(Fmt.plural(outingsToday, "выход", "выхода", "выходов")) из \(usual) за день"
        }
        return "\(outingsToday) \(Fmt.plural(outingsToday, "выход", "выхода", "выходов")) за день — "
            + "как обычно"
    }

    private var voiceOver: String {
        if let session {
            return session.isPaused ? "Выход на паузе" : "Идёт выход"
        }
        guard let indoors else { return "Сегодня ещё не выходили" }
        return "На улице были \(Fmt.duration(indoors)) назад. " + (support ?? "")
    }
}
