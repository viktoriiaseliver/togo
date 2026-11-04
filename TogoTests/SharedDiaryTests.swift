import Testing
import Foundation
import SwiftData
@testable import Togo

/// Правила спора двух телефонов об одной записи.
///
/// Это единственное место в обмене, где ошибка стоит дорого: потерянная
/// отметка кормления — испорченный день, потерянная отметка дозы —
/// вторая таблетка.
@Suite("Общий дневник · слияние")
struct SharedDiaryMergeTests {

    private func event(
        _ id: UUID = UUID(),
        grams: Int? = nil,
        note: String? = nil,
        deletedAt: Date? = nil,
        changedAt: Date
    ) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(),
                     authorName: "Вика", note: note, outcome: nil,
                     durationSeconds: nil, stoolForm: nil, stoolFlags: [],
                     grams: grams, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil,
                     deletedAt: deletedAt, deletedBy: nil, changedAt: changedAt)
    }

    private func dose(
        _ id: UUID = UUID(),
        givenAt: Date? = nil,
        givenBy: String? = nil,
        skippedAt: Date? = nil,
        claimedAt: Date? = nil,
        claimedBy: String? = nil,
        changedAt: Date
    ) -> DosePayload {
        DosePayload(id: id, medicationID: nil, medicationName: nil, scheduledAt: Date(),
                    givenAt: givenAt, givenBy: givenBy,
                    skippedAt: skippedAt, skippedBy: skippedAt == nil ? nil : "Наталья",
                    claimedBy: claimedBy, claimedAt: claimedAt,
                    cancelledAt: nil, cancelReason: nil, changedAt: changedAt)
    }

    // MARK: Записи дневника

    @Test("Правивший позже выигрывает")
    func laterWins() {
        let id = UUID()
        let now = Date()
        let mine = event(id, grams: 75, changedAt: now)
        let theirs = event(id, grams: 65, changedAt: now.addingTimeInterval(-60))

        #expect(SharedDiaryMerge.resolve(local: mine, remote: theirs).grams == 75)
        #expect(SharedDiaryMerge.resolve(local: theirs, remote: mine).grams == 75)
    }

    @Test("Удаление сильнее чужой правки")
    func deletionBeatsEdit() {
        let id = UUID()
        let now = Date()
        let deleted = event(id, deletedAt: now, changedAt: now)
        let edited = event(id, note: "поправила", changedAt: now.addingTimeInterval(-30))

        #expect(SharedDiaryMerge.resolve(local: deleted, remote: edited).deletedAt != nil)
        #expect(SharedDiaryMerge.resolve(local: edited, remote: deleted).deletedAt != nil,
                "«я удалила, а оно вернулось» ломает доверие к дневнику целиком")
    }

    @Test("Возврат удалённого позже — сильнее удаления")
    func restoreAfterDeleteWins() {
        let id = UUID()
        let now = Date()
        let deleted = event(id, deletedAt: now.addingTimeInterval(-60), changedAt: now.addingTimeInterval(-60))
        let restored = event(id, changedAt: now)

        #expect(SharedDiaryMerge.resolve(local: deleted, remote: restored).deletedAt == nil)
    }

    @Test("При равном времени выигрывает не пустая версия")
    func fullerWinsOnTie() {
        let id = UUID()
        let now = Date()
        let full = event(id, grams: 75, note: "Edgar Cooper", changedAt: now)
        let empty = event(id, changedAt: now)

        #expect(SharedDiaryMerge.resolve(local: empty, remote: full).grams == 75,
                "часы двух телефонов расходятся на секунды — при ничьей берём ту, где данных больше")
    }

    // MARK: Дозы

    @Test("Отметка «дано» не теряется никогда")
    func givenNeverLost() {
        let id = UUID()
        let now = Date()
        let given = dose(id, givenAt: now.addingTimeInterval(-600), givenBy: "Аня",
                         changedAt: now.addingTimeInterval(-600))
        let untouched = dose(id, changedAt: now)

        #expect(SharedDiaryMerge.resolve(local: untouched, remote: given).givenAt != nil)
        #expect(SharedDiaryMerge.resolve(local: given, remote: untouched).givenAt != nil)
        #expect(SharedDiaryMerge.resolve(local: untouched, remote: given).givenBy == "Аня")
    }

    @Test("Из двух отметок «дано» берётся более ранняя")
    func earliestGivenWins() {
        let id = UUID()
        let now = Date()
        let early = dose(id, givenAt: now.addingTimeInterval(-900), givenBy: "Аня",
                         changedAt: now.addingTimeInterval(-900))
        let late = dose(id, givenAt: now, givenBy: "Вика", changedAt: now)

        let merged = SharedDiaryMerge.resolve(local: late, remote: early)
        #expect(merged.givenAt == early.givenAt,
                "от отметки считается окно натощак — ошибаться безопаснее в раннюю сторону")
        #expect(merged.givenBy == "Аня")
    }

    @Test("Дали — значит не пропустили")
    func givenClearsSkip() {
        let id = UUID()
        let now = Date()
        let given = dose(id, givenAt: now, givenBy: "Аня", changedAt: now)
        let skipped = dose(id, skippedAt: now.addingTimeInterval(60),
                           changedAt: now.addingTimeInterval(60))

        let merged = SharedDiaryMerge.resolve(local: skipped, remote: given)
        #expect(merged.givenAt != nil)
        #expect(merged.skippedAt == nil)
    }

    @Test("Пропуск не стирается чужой тишиной")
    func skipSurvives() {
        let id = UUID()
        let now = Date()
        let skipped = dose(id, skippedAt: now.addingTimeInterval(-300),
                           changedAt: now.addingTimeInterval(-300))
        let untouched = dose(id, changedAt: now)

        #expect(SharedDiaryMerge.resolve(local: untouched, remote: skipped).skippedAt != nil)
        #expect(SharedDiaryMerge.resolve(local: untouched, remote: skipped).skippedBy == "Наталья")
    }

    @Test("«Беру на себя» держится за тем, кто взял раньше")
    func earliestClaimWins() {
        let id = UUID()
        let now = Date()
        let first = dose(id, claimedAt: now.addingTimeInterval(-120), claimedBy: "Аня",
                         changedAt: now.addingTimeInterval(-120))
        let second = dose(id, claimedAt: now, claimedBy: "Вика", changedAt: now)

        #expect(SharedDiaryMerge.resolve(local: second, remote: first).claimedBy == "Аня",
                "иначе двое перехватывают дозу друг у друга по кругу")
    }
}

/// Приём чужих записей в свою базу.
@Suite("Общий дневник · приём")
@MainActor
struct SharedDiaryInboxTests {

    private func setup() throws -> (ModelContext, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        try context.save()
        return (context, dog)
    }

    private func payload(_ id: UUID, grams: Int?, changedAt: Date, deletedAt: Date? = nil) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(), authorName: "Аня",
                     note: nil, outcome: nil, durationSeconds: nil, stoolForm: nil,
                     stoolFlags: [], grams: grams, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil, deletedAt: deletedAt,
                     deletedBy: nil, changedAt: changedAt)
    }

    @Test("Чужая запись появляется в дневнике")
    func newEventArrives() throws {
        let (context, dog) = try setup()
        SharedDiaryInbox.accept(payload(UUID(), grams: 65, changedAt: Date()),
                                dog: dog, context: context)

        #expect(dog.events.count == 1)
        #expect(dog.events.first?.grams == 65)
        #expect(dog.events.first?.authorName == "Аня")
    }

    @Test("Та же запись второй раз не задваивается")
    func idempotent() throws {
        let (context, dog) = try setup()
        let one = payload(UUID(), grams: 65, changedAt: Date())

        SharedDiaryInbox.accept(one, dog: dog, context: context)
        SharedDiaryInbox.accept(one, dog: dog, context: context)

        #expect(dog.events.count == 1)
    }

    @Test("Чужая правка накатывается на свою запись")
    func remoteEditApplied() throws {
        let (context, dog) = try setup()
        let id = UUID()
        let now = Date()

        SharedDiaryInbox.accept(payload(id, grams: 65, changedAt: now.addingTimeInterval(-60)),
                                dog: dog, context: context)
        SharedDiaryInbox.accept(payload(id, grams: 75, changedAt: now),
                                dog: dog, context: context)

        #expect(dog.events.count == 1)
        #expect(dog.events.first?.grams == 75)
    }

    @Test("Своя более свежая правка чужой не затирается")
    func localNewerSurvives() throws {
        let (context, dog) = try setup()
        let id = UUID()
        let now = Date()

        SharedDiaryInbox.accept(payload(id, grams: 75, changedAt: now), dog: dog, context: context)
        let needsPush = SharedDiaryInbox.accept(payload(id, grams: 65, changedAt: now.addingTimeInterval(-60)),
                                                dog: dog, context: context)

        #expect(dog.events.first?.grams == 75)
        #expect(needsPush == .вернуть, "наша версия победила — значит её надо отправить обратно")
    }

    @Test("Чужое удаление доходит")
    func remoteDeletionApplied() throws {
        let (context, dog) = try setup()
        let id = UUID()
        let now = Date()

        SharedDiaryInbox.accept(payload(id, grams: 65, changedAt: now.addingTimeInterval(-60)),
                                dog: dog, context: context)
        SharedDiaryInbox.accept(payload(id, grams: 65, changedAt: now, deletedAt: now),
                                dog: dog, context: context)

        #expect(dog.events.first?.isDeleted == true)
        #expect(Diary.active(dog.events).isEmpty)
    }
}
