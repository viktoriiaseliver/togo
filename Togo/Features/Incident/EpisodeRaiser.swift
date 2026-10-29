import SwiftUI
import SwiftData

/// Второй инцидент за сутки поднимает эпизод — откуда бы он ни пришёл.
///
/// **До 29.10.2026 правило жило приватной функцией `IncidentSheet`**,
/// и эпизод поднимала только шторка «Что случилось». Инцидент,
/// отмеченный на прогулке (`WalkMode.finish`), дописанный с блокировки
/// или записанный голосом (`WalkControl.finish`), в счёт попадал —
/// `Diary.incidentsInLast24h` читает ленту целиком, — а эпизод не
/// поднимал никогда. Две рвоты за вечер, обе на прогулке: вердикты
/// «просится» продолжали говорить «терпит», как будто ничего не было.
///
/// > Правило, которое спрашивают с одной двери, на остальных
/// > не действует, — и молчит об этом.
///
/// # Туалет дома эпизода не поднимает
///
/// С 29.10 лужа и кучка дома записываются инцидентом всегда (решение
/// Виктории: «всё, что случилось дома по поводу луж и туалета, —
/// в инциденте»). У щенка их бывает пять за день, и это обучение,
/// а не болезнь: считай мы их, эпизод висел бы неделями и гасил
/// вердикты ровно у того, кому они нужнее всего. Поэтому счёт идёт
/// по `IncidentKind.raisesEpisode`, а лужи остаются в сводке врачу.
@MainActor
enum EpisodeRaiser {

    /// Поднять или продлить эпизод, если инцидентов набралось.
    ///
    /// `appState` пуст у голосового пути — там эпизод ищется в базе,
    /// а экран подтянет его сам при открытии (`refreshEpisode`).
    /// Возвращает `false`, только если эпизод был нужен и не сохранился.
    @discardableResult
    static func afterIncident(dog: Dog, context: ModelContext,
                              appState: AppState?, now: Date = Date()) -> Bool {
        let recent = Diary.episodeIncidentsInLast24h(dog.events, now: now)
        guard recent.count >= 2 else { return true }

        // Ещё один инцидент — не новый эпизод, а продолжение старого.
        let идущие = (try? context.fetch(FetchDescriptor<Episode>())) ?? []
        if let running = идущие.filter({ $0.isActive(at: now) })
            .max(by: { $0.lastIncidentAt < $1.lastIncidentAt }) {
            let былоПоследним = running.lastIncidentAt
            let былКонец = running.endedAt
            running.extend(to: recent.map(\.date).max() ?? now)
            guard context.persist(otherwise: {
                running.lastIncidentAt = былоПоследним
                running.endedAt = былКонец
            }) else {
                appState?.showFailure("Эпизод не продлился · отметь ещё раз")
                return false
            }
            appState?.activeEpisode = running
            return true
        }

        let episode = Episode(
            title: "Эпизод",
            detail: "Два инцидента за сутки. Вердикты «просится» на паузе, пока не станет понятно, что происходит.",
            startedAt: recent.map(\.date).min() ?? now
        )
        episode.extend(to: recent.map(\.date).max() ?? now)
        context.insert(episode)

        // `appState.activeEpisode` ставится только после удачного сохранения.
        // Раньше здесь стоял `try?`, и эпизод открывался на экране, не
        // существуя в хранилище: вердикты «просится» гасли, объяснения
        // этому в дневнике не было, а после перезапуска эпизод исчезал
        // вместе с причиной, по которой приложение замолчало.
        guard context.persist(otherwise: { context.delete(episode) }) else {
            appState?.showFailure("Эпизод не завёлся · отметь ещё раз")
            return false
        }
        appState?.activeEpisode = episode
        return true
    }
}
