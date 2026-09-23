import Testing
import Foundation
@testable import Togo

/// Формы числа берутся из каталога, а не из кода.
///
/// До 23.09 в `Fmt.plural` жил собственный выбор формы с русскими
/// словами внутри: шесть наборов, 31 место вызова. Логика была верная,
/// включая исключение 11–14, а словарь — один и русский. Украинец увидел
/// бы русские слова, сколько каталог ни переводи, и ни один сторож
/// этого не показывал: слова лежали в аргументах функции, а не в `Text`.
///
/// Проверяем на 1, 2, 5 и **11**: одиннадцать ловит ровно тот диапазон,
/// где «по последней цифре» ломается, — 11 кончается на 1, а форма
/// нужна как у пяти.
@Suite("Формы числа")
struct PluralFormTests {

    @Test("День, выход, минута, раз, запись, действие")
    func шестьНаборов() {
        #expect(Fmt.days(1) == "1 день")
        #expect(Fmt.days(2) == "2 дня")
        #expect(Fmt.days(5) == "5 дней")
        #expect(Fmt.days(11) == "11 дней", "одиннадцать — не «11 день»")

        #expect(Fmt.outings(1) == "1 выход")
        #expect(Fmt.outings(21) == "21 выход", "двадцать один — как один")
        #expect(Fmt.outings(11) == "11 выходов")

        #expect(Fmt.minutes(1) == "1 минута")
        #expect(Fmt.minutes(3) == "3 минуты")
        #expect(Fmt.minutes(12) == "12 минут")

        #expect(Fmt.times(1) == "1 раз")
        #expect(Fmt.times(2) == "2 раза")
        #expect(Fmt.times(5) == "5 раз")

        #expect(Fmt.records(1) == "1 запись")
        #expect(Fmt.records(2) == "2 записи")
        #expect(Fmt.records(114) == "114 записей", "сто четырнадцать — как пять")

        #expect(Fmt.actions(1) == "1 действие")
        #expect(Fmt.actions(4) == "4 действия")
        #expect(Fmt.actions(5) == "5 действий")
    }

    /// Строка, на которой переводчица поймала дефект в живом релизе:
    /// «из 1 кормлений».
    @Test("«из N кормлений» не ломается на единице")
    func изКормлений() {
        #expect(String(localized: "из \(1) кормлений") == "из 1 кормления")
        #expect(String(localized: "из \(2) кормлений") == "из 2 кормлений")
        #expect(String(localized: "из \(5) кормлений") == "из 5 кормлений")
    }

    /// Собственной плюрализации в коде больше нет. Если она вернётся,
    /// вернётся и русский словарь внутри неё.
    @Test("Своей функции выбора формы в коде нет")
    func своейФункцииНет() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var найдено: [String] = []
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            let база = корень.appendingPathComponent(каталог)
            let обход = FileManager.default.enumerator(at: база, includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "swift",
                      let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }
                if текст.contains("Fmt.plural(") || текст.contains("func plural(") {
                    найдено.append(элемент.lastPathComponent)
                }
            }
        }
        #expect(найдено.isEmpty, """
            собственный выбор формы вернулся: \(найдено).
            Формы живут в каталоге — там их умеет менять переводчик
            и там они есть для каждого языка. В коде словарь всегда один.
            """)
    }
}
