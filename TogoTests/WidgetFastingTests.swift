import Testing
import Foundation
import SwiftData
@testable import Togo

/// Виджет считает окно «не кормить» тем же правилом, что и экран.
///
/// **Здесь лежала третья реализация.** `LiveActivityController.fastingEnd`
/// перебирал лекарства руками и складывал `givenAt + fastingMinutes` —
/// то есть знал только окно ПОСЛЕ отметки приёма. Значит на локскране
/// молчали два случая из трёх:
///
/// - окно ДО дозы: к приёму желудок должен быть пустым, и «покормили
///   в 20:55, таблетка в 21:00» — это не натощак;
/// - сдвиг часа приёма: передвинули таблетку с 7:00 на 9:00, а виджет
///   по-прежнему пишет «не кормить до 8:00».
///
/// Главный экран это правило уже знал (`FeedingGate`, сведён в один
/// расчёт 23.09.2026). Правка была сделана на одной поверхности из трёх
/// — та же болезнь, что у Timer с подписью на «острове».
///
/// **И сторож этого не ловил.** `FastingWindowSecondImplementationTests`
/// ищет вызовы `fastingEnds(`; здесь расчёт был написан вручную
/// и ничего не звал. Сторож на вызов ловит «не позвали» и слеп
/// к «посчитали сами».
@Suite("Окно натощак на виджете следует за расписанием")
@MainActor
struct WidgetFastingTests {

    private func собака(часы: [Int], послеДозы: Int, доДозы: Int) throws -> (ModelContext, Dog) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        dog.isOnTreatment = true
        context.insert(dog)
        let лекарство = Medication(name: "Эутирокс", doseText: "50 мкг",
                                   times: часы, fastingMinutes: послеДозы)
        лекарство.fastingBeforeMinutes = доДозы
        лекарство.dog = dog
        context.insert(лекарство)
        try context.save()
        return (context, dog)
    }

    private func час(_ h: Int, _ m: Int = 0) -> Date {
        let день = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(minuteOfDay: h * 60 + m, on: день) ?? день
    }

    /// То, о чём виджет молчал: окно ПЕРЕД дозой.
    @Test("Виджет закрывает еду перед дозой, а не только после")
    func окноДоДозыВидно() throws {
        let (_, dog) = try собака(часы: [9 * 60], послеДозы: 60, доДозы: 60)
        let окно = FeedingGate.block(for: dog.medications, now: час(8, 30))
        #expect(окно?.freeAt == час(9), """
            виджет знал только окно после отметки приёма: человек
            кормит в 8:30, таблетка в 9:00, и она не всасывается.
            """)
    }

    @Test("Передвинули приём — на виджете передвинулось окно")
    func окноСледуетЗаЧасом() throws {
        let (context, dog) = try собака(часы: [9 * 60], послеДозы: 60, доДозы: 60)
        #expect(FeedingGate.block(for: dog.medications, now: час(8, 30)) != nil)

        dog.medications.first?.times = [12 * 60]
        try context.save()

        #expect(FeedingGate.block(for: dog.medications, now: час(8, 30)) == nil,
                "окно осталось у старого часа — человек не покормит тогда, когда уже можно")
        #expect(FeedingGate.block(for: dog.medications, now: час(11, 30))?.freeAt == час(12),
                "окно не переехало за дозой")
    }

    /// Сторож на ВЫЗОВ: расчёт окна в проекте остался один, и виджет
    /// его зовёт, а не повторяет.
    @Test("Виджет зовёт общее правило, а не считает сам")
    func виджетЗовётПравило() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let исходник = try String(
            contentsOf: корень.appendingPathComponent("Togo/Store/LiveActivityController.swift"),
            encoding: .utf8)

        #expect(исходник.contains("FeedingGate.block("), """
            снимок для виджета снова считает окно натощак сам.
            Правило одно — FeedingGate; вторая реализация знает только
            окно после отметки и молча не следует за сдвигом часа.
            """)
        #expect(!исходник.contains("addingTimeInterval(Double(medication.fastingMinutes)"), """
            в снимке снова сложение `givenAt + fastingMinutes` руками —
            ровно та строка, из-за которой виджет молчал про окно
            перед дозой.
            """)
    }

    /// Еда в снимке — то, ради чего приложение открывают.
    @Test("Снимок виджета знает про еду")
    func снимокЗнаетПроЕду() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let виджет = try String(
            contentsOf: корень.appendingPathComponent("TogoWidgets/TodayWidget.swift"),
            encoding: .utf8)

        #expect(виджет.contains("snapshot.lastMealAt"), """
            замер по журналу: пять сессий из четырнадцати начинаются
            с записи еды, и еда — самое частое действие вообще.
            Приложение открывают, чтобы покормить.
            """)
        #expect(виджет.contains("mealsPlanned"), "«сколько из скольких» — ответ на «уже кормили?»")
    }

    @Test("Пустой снимок не врёт про еду")
    func пустойСнимокЧестен() {
        #expect(WidgetSnapshot.empty.lastMealAt == nil)
        #expect(WidgetSnapshot.empty.mealsToday == 0)
        #expect(WidgetSnapshot.empty.mealsPlanned == 0, """
            «0 из 2» у собаки, которой ещё нет, читается как «не кормили»
            — а мы просто ничего не знаем.
            """)
    }
}
