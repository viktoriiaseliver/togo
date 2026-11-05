import Testing
import Foundation
import SwiftData
@testable import Togo

/// Анализы крови «через N недель» уходят и возвращаются вместе со схемой
/// (решение Виктории 29.10.2026, `КонтрольКрови`).
@Suite("Контроль крови живёт вместе со схемой")
@MainActor
struct КонтрольКровиTests {
    private let сейчас = Date()

    private func собакаСоСхемой() throws -> (ModelContext, Dog, Medication) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)
        let схема = Medication(name: "Эутирокс", doseText: "0,1 мг", times: [8 * 60])
        схема.dog = dog
        context.insert(схема)
        try context.save()
        return (context, dog, схема)
    }

    private func дело(_ context: ModelContext, _ dog: Dog, недели: Int, через дней: Int,
                      деталь: String = "Эутирокс · 0,1 мг", сделано: Bool = false) -> CareTask {
        let дело = CareTask(title: КонтрольКрови.заголовок(недели: недели), detail: деталь,
                            kind: .dated, intervalDays: 0, category: .medical,
                            lastDone: сделано ? сейчас : nil,
                            scheduledDate: сейчас.addingTimeInterval(Double(дней) * 86_400))
        дело.dog = dog
        context.insert(дело)
        return дело
    }

    @Test("Отмена схемы снимает будущие анализы; сделанные и чужие остаются")
    func отменаСнимает() throws {
        let (context, dog, схема) = try собакаСоСхемой()
        let будущее = дело(context, dog, недели: 4, через: 10)
        let сделанное = дело(context, dog, недели: 3, через: 3, сделано: true)
        let чужое = дело(context, dog, недели: 5, через: 12, деталь: "Ветмедин · 1 таб")
        try context.save()

        схема.отменить(в: сейчас, заметка: "курс завершён")

        #expect(будущее.deletedAt == сейчас)
        #expect(сделанное.deletedAt == nil)
        #expect(чужое.deletedAt == nil)
    }

    @Test("Возврат схемы в строй возвращает ровно снятые ею анализы")
    func возвратВозвращает() throws {
        let (context, dog, схема) = try собакаСоСхемой()
        let будущее = дело(context, dog, недели: 6, через: 20)
        let удалённоеРаньше = дело(context, dog, недели: 8, через: 30)
        удалённоеРаньше.deletedAt = сейчас.addingTimeInterval(-3600)
        try context.save()

        схема.отменить(в: сейчас)
        схема.вернутьВСтрой()

        #expect(будущее.deletedAt == nil)
        #expect(удалённоеРаньше.deletedAt != nil, "дело, удалённое человеком раньше, не воскресает")
    }

    @Test("Прошедшая неделя считается прошедшей, сегодняшняя — нет")
    func прошедшиеНедели() {
        #expect(КонтрольКрови.прошла(сейчас.addingTimeInterval(-2 * 86_400), now: сейчас))
        #expect(!КонтрольКрови.прошла(сейчас, now: сейчас))
        #expect(!КонтрольКрови.прошла(сейчас.addingTimeInterval(86_400), now: сейчас))
    }
}
