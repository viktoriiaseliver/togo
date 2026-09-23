import Testing
import Foundation
import SwiftData
@testable import Togo

/// Сдвинули час приёма — сдвинулось и окно «не кормить».
///
/// Эутирокс дают натощак, и окно перед дозой — не украшение: покормили
/// в него, и таблетка не всосалась. Если человек передвинул приём
/// с 7:00 на 9:00, а предупреждение осталось про 7:00, он покормит
/// собаку ровно тогда, когда нельзя, — и будет уверен, что всё сделал
/// правильно.
@Suite("Окно натощак следует за расписанием")
@MainActor
struct FastingWindowFollowsScheduleTests {

    private func собакаСЭутироксом(часы: [Int]) throws -> (ModelContext, Medication) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.isOnTreatment = true
        context.insert(dog)
        let лекарство = Medication(name: "Эутирокс", doseText: "50 мкг",
                                   times: часы, fastingMinutes: 60)
        лекарство.dog = dog
        context.insert(лекарство)
        try context.save()
        return (context, лекарство)
    }

    private func полдень(_ час: Int, _ минута: Int = 0) -> Date {
        let день = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(minuteOfDay: час * 60 + минута, on: день) ?? день
    }

    @Test("Окно закрывает еду за час до дозы")
    func окноПередДозой() throws {
        let (_, лекарство) = try собакаСЭутироксом(часы: [9 * 60])
        let блок = FeedingGate.block(for: [лекарство], now: полдень(8, 30))
        #expect(блок?.medication == "Эутирокс")
        #expect(блок?.freeAt == полдень(9))
    }

    @Test("Передвинули приём — передвинулось и окно")
    func окноСледуетЗаЧасом() throws {
        let (context, лекарство) = try собакаСЭутироксом(часы: [9 * 60])

        // В 8:30 кормить нельзя: до дозы в 9:00 меньше часа.
        #expect(FeedingGate.block(for: [лекарство], now: полдень(8, 30)) != nil)

        // Человек передвинул приём на 12:00.
        лекарство.times = [12 * 60]
        try context.save()

        // Старое окно должно исчезнуть…
        #expect(FeedingGate.block(for: [лекарство], now: полдень(8, 30)) == nil,
                "окно осталось у старого часа — человек не покормит тогда, когда уже можно")
        // …а новое появиться.
        let новое = FeedingGate.block(for: [лекарство], now: полдень(11, 30))
        #expect(новое?.freeAt == полдень(12),
                "окно не переехало за дозой — человек покормит ровно тогда, когда нельзя")
    }

    @Test("Окно натощак изменили — изменилась и его длина")
    func длинаОкнаСледуетЗаНастройкой() throws {
        let (context, лекарство) = try собакаСЭутироксом(часы: [9 * 60])
        #expect(FeedingGate.block(for: [лекарство], now: полдень(7, 30)) == nil)

        лекарство.fastingMinutes = 180
        try context.save()

        #expect(FeedingGate.block(for: [лекарство], now: полдень(7, 30)) != nil,
                "окно на три часа не закрыло еду за полтора часа до дозы")
    }
}

/// Напоминание о конце окна тоже обязано следовать за расписанием.
///
/// `ReminderScheduler` берёт окно у `DoseScheduler.fastingEnds` — то есть
/// знает только окно после отметки. Это записано здесь, чтобы следующий
/// не искал заново: на главном экране расчёт уже общий (`FeedingGate`),
/// в напоминаниях — ещё нет.
@Suite("Окно натощак: что ещё считает по-своему")
struct FastingWindowSecondImplementationTests {

    @Test("Расчёт окна в проекте остался один")
    func расчётОдин() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var места: [String] = []
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            let обход = FileManager.default.enumerator(
                at: корень.appendingPathComponent(каталог), includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "swift",
                      let текст = try? String(contentsOf: элемент, encoding: .utf8)
                else { continue }
                // Комментарии вычёркиваем. 23.09.2026 сторож покраснел
                // на строке `fastingEnds(` внутри пояснения к починке —
                // то есть на файле, который расчёт как раз перестал
                // повторять. Тест, ищущий строку в исходнике, не
                // отличает код от рассказа о коде, и красный без
                // дефекта учит не верить красному.
                let код = текст.components(separatedBy: .newlines)
                    .map { строка -> String in
                        let без = строка.components(separatedBy: "///")[0]
                        return без.components(separatedBy: "//")[0]
                    }
                    .joined(separator: "\n")
                guard код.contains("fastingEnds(") else { continue }
                места.append(элемент.lastPathComponent)
            }
        }
        #expect(места.sorted() == ["DoseScheduler.swift", "ReminderScheduler.swift"], """
            расчёт окна натощак разошёлся: \(места.sorted()).
            Правило одно — FeedingGate. Второй расчёт знает только окно
            после отметки приёма и молча не следует за сдвигом часа.
            """)
    }
}
