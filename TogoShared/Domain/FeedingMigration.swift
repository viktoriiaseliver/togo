import Foundation
import SwiftData

/// Разовое приведение питания к одному числу.
///
/// Раньше количество еды хранилось двумя полями сразу — «порция за раз»
/// и «норма в день», — и какое из них главное, решала ветка в коде.
/// На живых устройствах поэтому встречаются собаки, у которых дневная
/// норма пустая, а есть только порция; и собаки, у которых заполнено оба
/// поля, причём они не сходятся между собой.
///
/// Здесь это выпрямляется один раз и молча: дневная норма заполняется,
/// порция становится её честной долей. Марка корма подтягивается из запаса,
/// потому что вводить её отдельно больше негде.
nonisolated enum FeedingMigration {
    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Int {
        guard let dogs = try? context.fetch(FetchDescriptor<Dog>()) else { return 0 }
        var changed = 0

        for dog in dogs {
            let before = (dog.dailyNormGrams, dog.portionGrams, dog.foodBrand)

            // Норма пустая — значит, человек вводил порцию за раз.
            // Прежняя арифметика была ровно такой, так что еды
            // у собаки не прибавится и не убавится.
            if dog.dailyNormGrams == nil {
                dog.setDailyGrams(max(0, dog.portionGrams * max(1, dog.mealsPerDay)))
            } else {
                // Норма есть — она и главная. Порция пересчитывается из неё:
                // раньше её можно было поменять отдельно, и на карточке
                // питания стояли рядом два числа, которые не сходились.
                dog.portionGrams = dog.servingGrams
            }

            // Марку теперь спрашивают только в запасе корма. У тех, кто
            // успел завести запас, поле в профиле могло остаться пустым
            // или отстать — берём то, чем кормят на самом деле.
            dog.syncSingleFoodShare()

            if let brand = primaryBrand(of: dog) {
                dog.foodBrand = brand
            }

            if (dog.dailyNormGrams, dog.portionGrams, dog.foodBrand) != before { changed += 1 }
        }

        if changed > 0 { try? context.save() }
        return changed
    }

    /// Чем кормят в основном: сухой корм, если он есть, иначе первый.
    /// Смешанное кормление обычно «сухой плюс банка сверху», и в подписи
    /// к кормлению человек ждёт увидеть именно мешок.
    static func primaryBrand(of dog: Dog) -> String? {
        let named = dog.stocks.filter { !$0.brand.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !named.isEmpty else { return nil }
        return (named.first { $0.kind == .dry } ?? named[0]).brand
    }
}

/// Разовое связывание отметок с их прогулками.
///
/// Живёт рядом с остальными починками: запускается один раз при старте
/// и молча выпрямляет то, что уже лежит на устройствах.
enum WalkLinkStartup {
    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Int {
        guard let events = try? context.fetch(FetchDescriptor<LogEvent>()) else { return 0 }
        let linked = WalkLinkMigration.link(events)
        if linked > 0 { try? context.save() }
        return linked
    }
}
