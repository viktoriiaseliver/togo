import SwiftUI
import SwiftData

/// Обмен виден экранам через окружение — как и всё остальное общее.
/// Может отсутствовать: пока общий дневник выключен, его просто нет.
private struct FamilySyncKey: EnvironmentKey {
    static let defaultValue: FamilySync? = nil
}

extension EnvironmentValues {
    var familySync: FamilySync? {
        get { self[FamilySyncKey.self] }
        set { self[FamilySyncKey.self] = newValue }
    }
}

/// Что приложение делает, когда обмен записал чужое.
///
/// **Зачем, 29.10.2026.** Снимок виджета и напоминания пересобирались
/// только главным экраном — тиком и `.task`. Чужая отметка, приехавшая
/// тихим пушем при свёрнутом приложении, ложилась в базу, а локскрин
/// и напоминания продолжали жить прежней картиной до открытия
/// «Сегодня». `FamilySync` лежит в `TogoShared` и до `ReminderScheduler`
/// и `LiveActivityController` (цель приложения) не дотягивается, поэтому
/// зовёт сюда обратным вызовом — тем же путём, что `дозаБольшеНеЖдёт`.
///
/// **Своих механизмов здесь нет, только два существующих входа**:
/// `LiveActivityController.publishSnapshot` и `ReminderScheduler.refresh`
/// — те же вызовы и с той же собакой, что у `TodayScreen.сЧасами`.
/// Их внутренности правятся в другом месте, и эта точка про них
/// не знает ничего, кроме подписи.
enum ЧужоеПринято {
    static func пересобрать(container: ModelContainer, appState: AppState, settings: Settings) {
        // Выборка под `do`: при отказе пересобирать не по чему, и
        // «собак нет» здесь было бы неправдой — напоминания по пустой
        // собаке пересобрались бы в ничто.
        let собаки: [Dog]
        do {
            собаки = try container.mainContext.fetch(FetchDescriptor<Dog>())
        } catch {
            log.error("""
                общий дневник: чужое принято, а собак прочесть не вышло — \
                виджет и напоминания пересоберутся при открытии экрана. \
                \(error.localizedDescription)
                """)
            return
        }
        let собака = appState.activeDog(from: собаки)
        LiveActivityController.publishSnapshot(dog: собака, appState: appState)
        Task { await ReminderScheduler.refresh(dog: собака, settings: settings) }
    }
}
