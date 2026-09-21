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
    /// Когда кончился последний записанный выход. Нужен не для счёта,
    /// а для честного ответа, когда считать уже нечего, — см. `silence`.
    var lastOutingEndedAt: Date?
    /// Идущий выход: пока он идёт, вопрос снят.
    let session: ActiveSession?
    let now: Date

    /// Дольше этого «давно ли гуляли» перестаёт быть ответом на вопрос.
    ///
    /// Сутки не из головы: вопрос, который задаёт этот экран, — «пора ли
    /// выходить», и он про часы. За сутками число отвечает уже не на него.
    ///
    /// **Зачем вообще потолок.** 21.09.2026 после восемнадцати дней без
    /// отметок экран показал «434 ч назад · на улице были». Это неправда,
    /// и неправда опасного сорта: приложение сказало **о собаке** то,
    /// чего не знало. Знало оно другое — что записей нет с 3 сентября.
    /// Та же форма дефекта, на которой проект уже обжигался: отсутствие
    /// записи показано как отсутствие события.
    static let silenceCeiling: TimeInterval = 24 * 3600
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
        } else if let silence {
            // Считать нечего — и мы говорим именно это, а не большее число.
            Text("Записей нет с \(Fmt.shortDay(silence))")
                .textStyle(AppFont.sectionTitle)
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

    private var silence: Date? {
        Self.silence(indoors: indoors, lastOutingEndedAt: lastOutingEndedAt)
    }

    /// Дата, с которой в журнале тишина, — если тишина перевалила за сутки.
    /// Пусто во всех остальных случаях, включая «выходили сегодня».
    ///
    /// Вынесено из вью нарочно: правило «за потолком говорим другое
    /// предложение, а не большее число» обязано проверяться тестом.
    /// Живя приватным свойством вью, оно держалось бы на честном слове
    /// до первой правки — а правка тут стоит доверия ко всему экрану.
    static func silence(indoors: TimeInterval?, lastOutingEndedAt: Date?) -> Date? {
        guard let indoors, indoors >= silenceCeiling,
              let lastOutingEndedAt else { return nil }
        return lastOutingEndedAt
    }

    /// Строка про режим. Появляется, только когда есть с чем сравнивать:
    /// «обычно чаще» по двум дням — это не наблюдение, а шум.
    private var support: String? {
        guard session == nil, rhythm.isReliable else { return nil }
        let usual = Int(rhythm.outingsPerDay.rounded())
        guard usual > 0 else { return nil }

        // `Fmt.plural` возвращает число ВМЕСТЕ со словом. Печатать число
        // перед ним — значит напечатать его дважды: «3 3 выхода за день».
        // Тот же дефект жил в строке «5 5 напоминаний ждут даты».
        let выходы = Fmt.plural(outingsToday, "выход", "выхода", "выходов")
        if outingsToday < usual {
            return "Обычно выходите чаще · \(выходы) из \(usual) за день"
        }
        return "\(выходы) за день — как обычно"
    }

    private var voiceOver: String {
        if let session {
            return session.isPaused ? "Выход на паузе" : "Идёт выход"
        }
        if let silence { return "Записей нет с \(Fmt.shortDay(silence))" }
        guard let indoors else { return "Сегодня ещё не выходили" }
        return "На улице были \(Fmt.duration(indoors)) назад. " + (support ?? "")
    }
}
