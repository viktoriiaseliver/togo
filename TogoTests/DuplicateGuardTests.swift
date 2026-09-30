import Testing
import Foundation
import SwiftData
@testable import Togo

/// Правило дубля одно на все пути записи.
///
/// Замер 23.09.2026 по журналу с телефона: 112 записей, два дубля еды —
/// через 6 и 8 секунд после записи, оба пойманы. То есть защита работает
/// там, где стоит. А стояла она ровно в одном месте: `EventLog`, то есть
/// экраны. Голос, кнопка «Действие» и ярлыки шли мимо — и это тот путь,
/// где на экран не смотрят, значит второй раз нажмут вероятнее.
@Suite("Дубль ловится на всех путях записи")
@MainActor
struct DuplicateGuardTests {

    private func собакаИКонтекст() throws -> (ModelContext, Dog) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    private func еда(_ context: ModelContext, _ dog: Dog, at date: Date) throws -> LogEvent {
        let event = LogEvent(kind: .meal, date: date, authorName: "Я")
        event.grams = 65
        event.dog = dog
        context.insert(event)
        try context.save()
        return event
    }

    @Test("Вторая еда через шесть секунд — дубль")
    func второйТапЛовится() throws {
        let (context, dog) = try собакаИКонтекст()
        let первая = Date()
        _ = try еда(context, dog, at: первая)

        let вторая = LogEvent(kind: .meal, date: первая.addingTimeInterval(6), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вторая.date,
                                      like: вторая, in: context) != nil)
    }

    @Test("За окном — не дубль: собаку правда кормят дважды в день")
    func заОкномНеДубль() throws {
        let (context, dog) = try собакаИКонтекст()
        let утро = Date()
        _ = try еда(context, dog, at: утро)

        let вечер = LogEvent(kind: .meal,
                             date: утро.addingTimeInterval(DuplicateGuard.window + 1),
                             authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вечер.date,
                                      like: вечер, in: context) == nil)
    }

    private func запись(_ kind: LogKind, _ context: ModelContext, _ dog: Dog,
                        at date: Date, прогулка: UUID? = nil) throws -> LogEvent {
        let event = LogEvent(kind: kind, date: date, authorName: "Я")
        event.walkEventID = прогулка
        event.dog = dog
        context.insert(event)
        try context.save()
        return event
    }

    /// Карточка быстрой записи обещает ловить двойной тап по любой кнопке.
    /// До 30.09 стул, лакомство и выход проходили дважды.
    @Test("Стул, лакомство и выход через пять секунд — дубль", arguments: [LogKind.stool, .treat, .outing])
    func кнопкиБыстройЗаписиЛовятся(_ kind: LogKind) throws {
        let (context, dog) = try собакаИКонтекст()
        let первый = Date()
        _ = try запись(kind, context, dog, at: первый)

        let второй = LogEvent(kind: kind, date: первый.addingTimeInterval(5), authorName: "Я")
        #expect(DuplicateGuard.recent(of: kind, dog: dog, at: второй.date,
                                      like: второй, in: context) != nil,
                "два тапа подряд по «\(kind.title)» — почти всегда промах")
    }

    @Test("Два инцидента подряд — не дубль: из них поднимается эпизод")
    func инцидентНеЛовится() throws {
        let (context, dog) = try собакаИКонтекст()
        let первый = Date()
        _ = try запись(.incident, context, dog, at: первый)

        let второй = LogEvent(kind: .incident, date: первый.addingTimeInterval(5), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .incident, dog: dog, at: второй.date,
                                      like: второй, in: context) == nil)
    }

    @Test("Отметки прогулки дублем не считаются: писал трижды за прогулку")
    func отметкиПрогулкиНеЛовятся() throws {
        let (context, dog) = try собакаИКонтекст()
        let прогулка = UUID()
        let первый = Date()
        _ = try запись(.outing, context, dog, at: первый, прогулка: прогулка)

        let второй = LogEvent(kind: .outing, date: первый.addingTimeInterval(20), authorName: "Я")
        второй.walkEventID = прогулка
        #expect(DuplicateGuard.recent(of: .outing, dog: dog, at: второй.date,
                                      like: второй, in: context) == nil,
                "собака и правда писает трижды за прогулку")

        // И наоборот: отметка прогулки не делает дублем выход с кнопки.
        let сКнопки = LogEvent(kind: .outing, date: первый.addingTimeInterval(30), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .outing, dog: dog, at: сКнопки.date,
                                      like: сКнопки, in: context) == nil)
    }

    @Test("Удалённая запись дублем не считается")
    func удалённаяНеСчитается() throws {
        let (context, dog) = try собакаИКонтекст()
        let первая = try еда(context, dog, at: Date())
        первая.deletedAt = Date()
        try context.save()

        let вторая = LogEvent(kind: .meal, date: первая.date.addingTimeInterval(3), authorName: "Я")
        #expect(DuplicateGuard.recent(of: .meal, dog: dog, at: вторая.date,
                                      like: вторая, in: context) == nil,
                "человек удалил запись и записывает заново — это не второй тап")
    }

    /// Сторож на ВЫЗОВ, а не на правило: правило можно вынести и забыть
    /// позвать. Именно это и было — `QuickLog` писал в дневник напрямую.
    @Test("Быстрая запись зовёт то же правило, что и экран")
    func быстраяЗаписьСпрашиваетСторожа() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        for путь in ["Togo/Store/EventLog.swift", "Togo/Intents/QuickLogIntents.swift"] {
            let исходник = try String(
                contentsOf: корень.appendingPathComponent(путь), encoding: .utf8)
            #expect(исходник.contains("DuplicateGuard.recent("), """
                \(путь) пишет в дневник, не спросив о дубле.
                Правило одно на все пути: голосом и кнопкой «Действие»
                жмут не глядя на экран — там второй раз вероятнее.
                """)
            #expect(исходник.contains("UsageLog.note(.record"), """
                \(путь) пишет в дневник молча: в замере этот путь
                не отличить от неиспользуемого.
                """)
        }
    }
}
