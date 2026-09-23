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

    /// Прежде здесь стоял один тест с неверной посылкой: «в тестовой сборке
    /// профиля нет — ровно тот же случай, что на телефоне с бесплатной
    /// командой». Случай не тот. У бесплатной команды профиль **есть**,
    /// просто без контейнеров iCloud; профиля нет у сборок из App Store
    /// и TestFlight, где право как раз выдано. Две разные вещи считались
    /// одной, и проверка закрепила дефект вместо того, чтобы его поймать.
    ///
    /// Цена: журнал запуска с телефона 22.09 на всех трёх запусках
    /// TestFlight писал «права на iCloud нет — только локально».
    /// Общий дневник не мог заработать ни у кого, типы `CD_*` в контейнере
    /// CloudKit не появились ни разу.
    @Test("На устройстве профиля нет только у сборки из App Store — право есть")
    func testFlightBuildHasCloud() {
        // Сборка 80 сказала четверым «У этой сборки нет права на iCloud»,
        // потому что различать App Store и тестовый бандл я пробовала
        // по чеку покупки. `appStoreReceiptURL` устарел, файла на новых
        // iOS нет, признак всегда ложный. Симулятор отсекается отдельной
        // веткой в `hasCloudEntitlement`, и здесь гадать больше не о чем.
        #expect(Persistence.cloudEntitlementGranted(profileExists: false,
                                                    entitlements: nil))
    }

    @Test("Бесплатная команда: профиль есть, контейнеров iCloud в нём нет")
    func freeTeamHasProfileWithoutCloud() {
        #expect(!Persistence.cloudEntitlementGranted(
            profileExists: true,
            entitlements: ["application-identifier": "ABCDE12345.app.togo.diary"]))
        #expect(!Persistence.cloudEntitlementGranted(
            profileExists: true,
            entitlements: ["com.apple.developer.icloud-container-identifiers": [String]()]))
    }

    @Test("Платная команда: контейнер назван в профиле — право есть")
    func paidTeamHasCloud() {
        #expect(Persistence.cloudEntitlementGranted(
            profileExists: true,
            entitlements: ["com.apple.developer.icloud-container-identifiers":
                            ["iCloud.app.togo.diary"]]))
    }

    @Test("Профиль есть, но не прочитался — синхронизацию не обещаем")
    func unreadableProfileIsRefused() {
        #expect(!Persistence.cloudEntitlementGranted(profileExists: true,
                                                     entitlements: nil))
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

    @Test("Состояние iCloud без зеркала — не «включён», и причина названа")
    func cloudStateHonest() async {
        _ = Persistence.appContainer()
        let state = await Persistence.cloudState()

        // Ровно одно состояние считается хорошим, и это не оно:
        // зеркала в симуляторе нет.
        #expect(!state.isGood)
        #expect(state != .syncing)

        // До 23.09.2026 здесь стояло `== .unavailable` — ответ, один
        // на три разные причины, и он же советовал включить iCloud
        // Drive. У тестовой сборки права на iCloud нет вовсе, так что
        // совет был бесполезен, а причина не названа.
        //
        // Я и сам ошибся, когда правил этот тест: решил, что в симуляторе
        // дело в отсутствии аккаунта. Замер сказал другое — дело в праве.
        // Разбор оказался точнее моей догадки о нём.
        #expect(state == .noEntitlement, """
            причина отказа стала \(state), а у тестовой сборки нет
            права на iCloud — значит разбор в `cloudState()` отвечает
            не о том, что измерил.
            """)
        #expect(!state.detail.isEmpty, "причина без текста человеку ничего не говорит")
    }

    @Test("Крошки запуска пишутся и читаются")
    func startupLog() {
        StartupLog.clear()
        StartupLog.note("проверка")
        #expect(StartupLog.read().contains("проверка"))
        StartupLog.clear()
    }
}
