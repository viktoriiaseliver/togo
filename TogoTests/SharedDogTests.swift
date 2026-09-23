import Testing
import Foundation
import SwiftData
@testable import Togo

/// Собака ездит в общем дневнике.
///
/// Отзыв хозяйки за один вечер дважды: «у неё нет половины функционала»
/// и «мама не видит то же, что и я, **и не видит мою собаку**». Причина
/// была одна: общая зона возила два типа записей из семи, и собаки среди
/// них не было. Приглашение работало и приводило в пустую комнату.
@Suite("Профиль собаки в общем дневнике")
@MainActor
struct SharedDogTests {

    private func снимок(имя: String = "Стич", вес: Double = 4.1,
                        изменено: Date = Date()) -> DogPayload {
        DogPayload(
            id: UUID(), name: имя, breed: nil, birthDate: nil,
            sex: DogSex.unknown.rawValue, isNeutered: false, weightKg: вес,
            targetWeightLow: nil, targetWeightHigh: nil,
            foodBrand: "", portionGrams: 60, mealsPerDay: 2,
            mealTimes: [450, 1110], dailyNormGrams: nil, forbiddenFoods: [],
            wakeMinuteOfDay: 420, sleepMinuteOfDay: 1380,
            isOnTreatment: false, chipNumber: nil, vetName: nil, vetPhone: nil,
            clinicName: nil, clinicPhone: nil, distinctiveMarks: nil,
            changedAt: изменено
        )
    }

    // MARK: Приём

    @Test("Приехавшая собака заводится у гостя")
    func собакаЗаводится() throws {
        let context = ModelContext(Persistence.container())
        let снимокСобаки = снимок(имя: "Стич", вес: 4.1)

        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)
        #expect(собаки.first?.id == снимокСобаки.id)
        #expect(собаки.first?.name == "Стич")
        #expect(собаки.first?.weightKg == 4.1)
    }

    /// Решение Виктории от 23.09.2026: обе, переключателем. Слияния
    /// по кличке быть не должно ни при каких условиях — две «Стич»
    /// в одном доме это две собаки, и живой дневник 23.09 разошёлся
    /// пополам именно так.
    @Test("Своя собака гостя остаётся рядом с приехавшей")
    func двеСобакиЖивутРядом() throws {
        let context = ModelContext(Persistence.container())
        let своя = Dog(name: "Стич", weightKg: 4.0)
        context.insert(своя)
        try context.save()

        SharedDiaryInbox.accept(снимок(имя: "Стич", вес: 4.1), context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 2, "приехавшая собака слилась со своей по кличке")
        #expect(собаки.contains { $0.weightKg == 4.0 })
        #expect(собаки.contains { $0.weightKg == 4.1 })
    }

    @Test("Повторный приезд правит ту же собаку, а не заводит вторую")
    func повторНеДублирует() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок(вес: 4.1, изменено: Date())
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        снимокСобаки.weightKg = 4.4
        снимокСобаки.changedAt = Date().addingTimeInterval(60)
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)
        #expect(собаки.first?.weightKg == 4.4)
    }

    // MARK: Спор

    @Test("Побеждает правка, что позже")
    func позжеПобеждает() {
        let раньше = снимок(вес: 4.0, изменено: Date())
        var позже = раньше
        позже.weightKg = 4.5
        позже.changedAt = раньше.changedAt.addingTimeInterval(30)

        #expect(SharedDiaryMerge.resolve(local: раньше, remote: позже).weightKg == 4.5)
        #expect(SharedDiaryMerge.resolve(local: позже, remote: раньше).weightKg == 4.5)
    }

    /// Часы двух телефонов расходятся на секунды. При ничьей разумнее
    /// взять ту версию, где данных больше, чем ту, где их стёрли.
    @Test("При ничьей выигрывает заполненное")
    func ничьяЗаЗаполненным() {
        let момент = Date()
        var пустая = снимок(изменено: момент)
        var полная = пустая
        полная.breed = "мальтипу"
        полная.vetName = "Клиника на углу"
        полная.chipNumber = "250269"
        пустая.breed = nil

        #expect(SharedDiaryMerge.resolve(local: пустая, remote: полная).breed == "мальтипу")
        #expect(SharedDiaryMerge.resolve(local: полная, remote: пустая).breed == "мальтипу")
    }

    /// Вкладка «Здоровье» приходит с курсом лечения. Если `isOnTreatment`
    /// не доедет, гость отмечает приёмы, которые ему негде посмотреть.
    @Test("Лечение доезжает вместе с профилем")
    func лечениеДоезжает() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок()
        снимокСобаки.isOnTreatment = true
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собака = try context.fetch(FetchDescriptor<Dog>()).first
        #expect(собака?.isOnTreatment == true)
    }

    // MARK: Кодирование

    @Test("Снимок переживает дорогу через CloudKit без потерь")
    func полеНеТеряется() throws {
        var исходный = снимок(имя: "Багира", вес: 5.2)
        исходный.breed = "такса"
        исходный.birthDate = Date(timeIntervalSince1970: 1_600_000_000)
        исходный.isNeutered = true
        исходный.targetWeightLow = 4.8
        исходный.targetWeightHigh = 5.5
        исходный.foodBrand = "Acana"
        исходный.dailyNormGrams = 180
        исходный.forbiddenFoods = ["виноград", "шоколад"]
        исходный.isOnTreatment = true
        исходный.chipNumber = "250269"
        исходный.vetName = "Мари"
        исходный.vetPhone = "+33..."
        исходный.clinicName = "Клиника на углу"
        исходный.clinicPhone = "+33..."
        исходный.distinctiveMarks = "белое пятно на груди"

        let зона = SharedDiaryRecords.zoneID()
        let запись = SharedDiaryRecords.record(исходный, in: зона)
        let вернувшийся = try #require(SharedDiaryRecords.dogPayload(запись))

        #expect(вернувшийся == исходный, """
            поле потерялось по дороге. Сравнение целиком, а не по одному:
            у словаря нельзя проверить тестом, что при переименовании
            ничего не выпало.
            """)
    }

    @Test("Запись без клички не принимается")
    func безКличкиНеПринимается() {
        let зона = SharedDiaryRecords.zoneID()
        let запись = SharedDiaryRecords.record(снимок(), in: зона)
        запись["name"] = nil
        #expect(SharedDiaryRecords.dogPayload(запись) == nil, """
            собака без клички — это не «пустое имя», а запись, которую
            нечем показать в переключателе.
            """)
    }

    // MARK: Привязка ленты

    @Test("Приехавшая запись цепляется к своей собаке, а не к первой")
    func записьИщетСвоюСобаку() throws {
        let context = ModelContext(Persistence.container())
        let чужая = Dog(name: "Стич", weightKg: 4.1)
        let своя = Dog(name: "Багира", weightKg: 5.2)
        context.insert(чужая)
        context.insert(своя)
        try context.save()

        var запись = EventPayload(
            id: UUID(), dogID: своя.id, kind: LogKind.meal.rawValue, date: Date(),
            authorName: "Мама", note: nil, outcome: nil, durationSeconds: nil,
            stoolForm: nil, stoolFlags: [], grams: 65, milliliters: nil,
            fromPortion: false, incidentKind: nil, incidentDetail: nil,
            walkEventID: nil, careTaskID: nil, medicationID: nil,
            deletedAt: nil, deletedBy: nil, changedAt: Date()
        )
        #expect(SharedDiaryInbox.dog(for: запись, context: context)?.id == своя.id)

        // Собаки, которой нет, — и двух местных: лучше ничья, чем
        // приписанная не тому животному. Ничью видно и можно починить.
        запись.dogID = UUID()
        #expect(SharedDiaryInbox.dog(for: запись, context: context) == nil)
    }

    @Test("Когда собака одна, запись без известного id достаётся ей")
    func однаСобакаЗабираетНичью() throws {
        let context = ModelContext(Persistence.container())
        let одна = Dog(name: "Стич", weightKg: 4.1)
        context.insert(одна)
        try context.save()

        let запись = EventPayload(
            id: UUID(), dogID: UUID(), kind: LogKind.meal.rawValue, date: Date(),
            authorName: "Мама", note: nil, outcome: nil, durationSeconds: nil,
            stoolForm: nil, stoolFlags: [], grams: 65, milliliters: nil,
            fromPortion: false, incidentKind: nil, incidentDetail: nil,
            walkEventID: nil, careTaskID: nil, medicationID: nil,
            deletedAt: nil, deletedBy: nil, changedAt: Date()
        )
        #expect(SharedDiaryInbox.dog(for: запись, context: context)?.id == одна.id, """
            записи, уехавшие до того, как профиль научился ездить, помнят
            чужой dogID. Когда собака одна, ошибиться невозможно.
            """)
    }
}
