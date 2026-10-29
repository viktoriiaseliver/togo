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
        // Гость, у которого открыта ПУСТАЯ собака, а из дневника пришла
        // собака с записями, — смотрит не туда. Ровно это и было у мамы
        // Виктории 29.10.2026: приглашение принято, уведомление пришло,
        // а на экране своя пустая собака, заведённая онбордингом,
        // и «ничего не работает». Переключаем один раз, только с пустой
        // на живую: собаку, у которой есть записи, гостю не подменяем.
        if SharedZoneOwner.isGuest,
           let открыта = appState.activeDog(from: собаки),
           Diary.active(открыта.events).isEmpty,
           let изДневника = собаки
               .filter({ $0.id != открыта.id && !Diary.active($0.events).isEmpty })
               .max(by: { $0.events.count < $1.events.count }) {
            appState.activeDogID = изДневника.id
        }
        let собака = appState.activeDog(from: собаки)
        LiveActivityController.publishSnapshot(dog: собака, appState: appState)
        // Владельцу — «Мама — в дневнике», когда она вошла (`ВошедшиеВДневник`).
        Task { await ВошедшиеВДневник.проверить() }
        Task { await ReminderScheduler.refresh(dog: собака, settings: settings) }
    }
}
