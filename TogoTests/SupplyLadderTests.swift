import Foundation
import Testing
@testable import Togo

/// Лестница запаса одна на корм и таблетки.
///
/// Заведено 07.10.2026 после замера библиотеки компонентов хендоффа:
/// у дизайна `stockLevel(daysLeft) → ok · low · out`, у нас лестница
/// была только у таблеток (`PillSupplyAdvisor.Level`, пороги 7 и 3),
/// а корм отвечал **булевым** `needsRestock`. Правило существовало
/// и до второй поверхности не дотянулось — наш класс «починка
/// на одной поверхности из двух».
///
/// **Эти тесты написаны от обратного.** Не «корм предупреждает»,
/// а «корм обязан отвечать ТОЙ ЖЕ ступенью, что таблетки на том же
/// числе дней»: утверждение «предупреждает» выполняется и при одной
/// ступени на всё, то есть при самом дефекте.
@Suite("Лестница запаса")
struct SupplyLadderTests {

    /// Первым — проверка, что сторожу было что сторожить.
    ///
    /// Без неё остальные молчали бы так же, как при всём хорошем:
    /// лестница из одной ступени прошла бы «совпадение корма
    /// с таблетками» на всех числах.
    @Test("У лестницы четыре различимые ступени")
    func ступенейЧетыре() {
        let ступени = [0, 2, 5, 30].map(PillSupplyAdvisor.level(days:))
        #expect(Set(ступени).count == 4,
                "ступени склеились: \(ступени) — различать нечем")
        #expect(ступени == [.out, .urgent, .low, .ok])
    }

    @Test("Корм и таблетки отвечают одинаково на одном числе дней")
    func кормСовпадаетСТаблетками() {
        for дней in 0...20 {
            let корм = FoodStock(kind: .dry, brand: "тест", packGrams: 1000,
                                 packsLeft: Double(дней) / 10.0, gramsPerDay: 100)
            let ступеньКорма = корм.level()
            let ступеньЛестницы = PillSupplyAdvisor.level(days: дней)
            #expect(ступеньКорма == ступеньЛестницы,
                    "на \(дней) дн. корм сказал \(ступеньКорма), а лестница — \(ступеньЛестницы)")
        }
    }

    /// Граница названа числом, а не «около недели»: порог живёт
    /// в `PillSupplyAdvisor`, и если кто-то заведёт у корма свой,
    /// разойдутся именно эти четыре значения.
    @Test("Границы ровно 7 и 3, и ноль — отдельная ступень")
    func границыНаМесте() {
        #expect(PillSupplyAdvisor.level(days: 8) == .ok)
        #expect(PillSupplyAdvisor.level(days: 7) == .low)
        #expect(PillSupplyAdvisor.level(days: 4) == .low)
        #expect(PillSupplyAdvisor.level(days: 3) == .urgent)
        #expect(PillSupplyAdvisor.level(days: 1) == .urgent)
        #expect(PillSupplyAdvisor.level(days: 0) == .out)
    }

    /// «Кончается через неделю» и «кончается завтра» обязаны быть
    /// РАЗНЫМИ — ровно это булево `needsRestock` и прятало.
    @Test("Неделя и день различимы у корма")
    func неделяИДеньРазличимы() {
        let наНеделю = FoodStock(kind: .dry, brand: "неделя", packGrams: 700,
                                 packsLeft: 1, gramsPerDay: 100)
        let наДень = FoodStock(kind: .dry, brand: "день", packGrams: 100,
                               packsLeft: 1, gramsPerDay: 100)
        #expect(наНеделю.level() == .low)
        #expect(наДень.level() == .urgent)
        #expect(наНеделю.level() != наДень.level(),
                "обе ступени совпали — вернулось булево")
    }

    /// `needsRestock` остаётся, но своего порога у него больше нет.
    /// Проверяем не «он работает», а «он ПЕРЕСКАЗЫВАЕТ лестницу»:
    /// заведи ему свой порог — и эти два утверждения разойдутся.
    @Test("needsRestock пересказывает лестницу, а не решает сам")
    func булевоПересказываетЛестницу() {
        for дней in 0...20 {
            let корм = FoodStock(kind: .dry, brand: "тест", packGrams: 1000,
                                 packsLeft: Double(дней) / 10.0, gramsPerDay: 100)
            #expect(корм.needsRestock() == (корм.level() != .ok),
                    "на \(дней) дн. булево и лестница разошлись")
        }
    }

    /// Корм без нормы в день не считается вовсе — и это `ok`,
    /// а не `out`: «не знаем» и «кончилось» разные новости.
    @Test("Без нормы в день — не считаем, а не «кончилось»")
    func безНормыНеСчитаем() {
        let корм = FoodStock(kind: .dry, brand: "без нормы", packGrams: 1000,
                             packsLeft: 0, gramsPerDay: 0)
        #expect(корм.daysLeft() == nil)
        #expect(корм.level() == .ok)
        #expect(корм.needsRestock() == false)
    }
}
