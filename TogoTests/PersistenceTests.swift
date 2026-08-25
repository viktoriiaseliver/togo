import Testing
import Foundation
import SwiftData
@testable import Togo

/// Падение на телефоне выглядело как «signal 5» — без строки и без причины.
/// Оказалось: SwiftData с CloudKit роняет приложение, если права на iCloud
/// нет. В симуляторе то же самое лишь пишет в лог, поэтому поймать это
/// можно было только на живом устройстве.
///
/// Эти проверки закрывают весь класс: хранилище открывается или честно
/// возвращает nil, но никогда не роняет приложение.
@Suite("Хранилище")
@MainActor
struct PersistenceTests {
    @Test("Хранилище приложения открывается и не падает")
    func appContainerOpens() {
        #expect(Persistence.appContainer() != nil)
    }

    @Test("Без профиля подписи права на iCloud нет — и CloudKit не трогаем")
    func noProfileMeansNoCloud() {
        // В тестовой сборке embedded.mobileprovision нет: ровно тот же
        // случай, что и на телефоне с бесплатной командой.
        #expect(!Persistence.hasCloudEntitlement)
        _ = Persistence.appContainer()
        #expect(!Persistence.isUsingCloud, "без права нельзя обещать синхронизацию")
    }

    @Test("Хранилище в памяти работает для тестов и превью")
    func inMemoryWorks() throws {
        let context = ModelContext(Persistence.container())
        context.insert(Dog(name: "Стич", weightKg: 4.1))
        #expect(try context.fetch(FetchDescriptor<Dog>()).count == 1)
    }

    @Test("Схема принимается CloudKit: все связи опциональны")
    func schemaIsCloudKitCompatible() {
        // CloudKit отказывается открывать хранилище, если хоть одна связь
        // не опциональна. Держим это проверкой, а не памятью.
        let dog = Dog(name: "Стич", weightKg: 4.1)
        #expect(dog.eventsStorage == nil)
        #expect(dog.medicationsStorage == nil)
        #expect(dog.events.isEmpty, "наружу торчит обычный массив")
        #expect(dog.medications.isEmpty)
    }

    @Test("Состояние iCloud без права — «недоступен», а не «включён»")
    func cloudStateHonest() async {
        _ = Persistence.appContainer()
        let state = await Persistence.cloudState()
        #expect(state == .unavailable)
        #expect(!state.isGood)
    }

    @Test("Крошки запуска пишутся и читаются")
    func startupLog() {
        StartupLog.clear()
        StartupLog.note("проверка")
        #expect(StartupLog.read().contains("проверка"))
        StartupLog.clear()
    }
}
