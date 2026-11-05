import Testing
import Foundation
import SwiftData
@testable import Togo

/// Экран «Данные и приватность» считает то же, что `Diary`, но дешевле.
///
/// До 05.11.2026 экран держал `@Query` без отбора и фильтровал
/// в `body`: при 1400 записях это весь дневник в памяти и порядка
/// 8400 проверок условия на каждую перерисовку — ради двух чисел.
/// Отбор уехал в базу (`DataPrivacyScreen.активнаяЗапись`), а число
/// дней считается по ОДНОЙ самой ранней строке
/// (`DataPrivacyScreen.самаяРанняяПервой`).
///
/// # Что именно проверяется
///
/// Не «предикат написан», а **что он даёт те же числа**, что честный
/// проход `Diary` по всему дневнику. Предикат здесь не переписан:
/// он берётся у экрана статикой, иначе тест сверял бы свою копию
/// сам с собой и остался бы зелёным при любом расхождении.
///
/// `#Predicate` не умеет звать `Diary.active`, поэтому копия условия
/// в коде всё же существует — одна, в экране. Этот тест и есть мост
/// между ней и `Diary`.
@Suite("«Данные и приватность»: отбор базы совпадает с Diary")
@MainActor
struct ДанныеИПриватностьСчётTests {

    private func дневник() throws -> (ModelContext, [LogEvent]) {
        let context = ModelContext(Persistence.container())
        let dog = Dog(name: "Стич", weightKg: 4.1)
        context.insert(dog)

        let сегодня = Date()
        var записи: [LogEvent] = []

        // Четыре живые записи, самая ранняя — девять дней назад.
        for день in [9, 5, 2, 0] {
            let событие = LogEvent(kind: .meal,
                                   date: сегодня.addingTimeInterval(TimeInterval(-день * 86_400)),
                                   authorName: "Я")
            событие.dog = dog
            context.insert(событие)
            записи.append(событие)
        }

        // Надгробие: удалённая запись. Считаться не должна.
        let удалённая = LogEvent(kind: .meal,
                                 date: сегодня.addingTimeInterval(-3 * 86_400),
                                 authorName: "Я")
        удалённая.dog = dog
        удалённая.deletedAt = сегодня
        context.insert(удалённая)
        записи.append(удалённая)

        // Запись прогрева схемы: 1 января 2001 года. Она и есть та,
        // из-за которой экран однажды печатал «9410 дней».
        let прогрев = LogEvent(kind: .note,
                               date: Date(timeIntervalSince1970: 978_307_200),
                               authorName: "ПРОГРЕВ СХЕМЫ")
        прогрев.dog = dog
        context.insert(прогрев)
        записи.append(прогрев)

        try context.save()
        return (context, записи)
    }

    @Test("Число записей и число дней совпадают с честным проходом")
    func отборБазыДаётТеЖеЧисла() throws {
        let (context, всё) = try дневник()

        // КОНТРОЛЬ ПЕРВЫМ, и он про фикстуру: в ней обязаны быть ОБА
        // вида записи, которые отбор должен выбросить. Без надгробия
        // и без служебной записи любое совпадение чисел было бы
        // совпадением на пустом месте.
        #expect(всё.count == 6, "в фикстуре \(всё.count) записей")
        #expect(всё.filter { $0.deletedAt != nil }.count == 1, "в фикстуре нет надгробия")
        #expect(всё.filter { Diary.служебная($0) }.count == 1, "в фикстуре нет служебной записи")
        #expect(Diary.active(всё).count == 4, "Diary считает активными \(Diary.active(всё).count)")

        // Предмет 1: отбор базы даёт ровно те записи, что `Diary.active`.
        let отобранные = try context.fetch(
            FetchDescriptor<LogEvent>(predicate: DataPrivacyScreen.активнаяЗапись)
        )
        #expect(Set(отобранные.map(\.id)) == Set(Diary.active(всё).map(\.id)),
                "база отобрала \(отобранные.count), Diary — \(Diary.active(всё).count)")

        // Предмет 2: одна строка даёт то же число дней, что весь дневник.
        // Здесь ловится обе беды сразу: и потерянное условие про
        // надгробие, и потерянное условие про служебную запись —
        // последняя сдвинула бы «дней» с 10 на ≈9400.
        let однаСтрока = try context.fetch(DataPrivacyScreen.самаяРанняяПервой)
        #expect(однаСтрока.count == 1, "самых ранних отобрано \(однаСтрока.count), а просили одну")
        #expect(Diary.daysOfData(однаСтрока) == Diary.daysOfData(всё),
                "по одной строке \(Diary.daysOfData(однаСтрока)) дней, по всему дневнику \(Diary.daysOfData(всё))")
        #expect(Diary.daysOfData(всё) == 10,
                "дней данных \(Diary.daysOfData(всё)) при самой ранней записи девять дней назад")
    }

    @Test("Отбор переживает дневник без единой живой записи")
    func пустойДневник() throws {
        let context = ModelContext(Persistence.container())
        let прогрев = LogEvent(kind: .note,
                               date: Date(timeIntervalSince1970: 978_307_200),
                               authorName: "ПРОГРЕВ СХЕМЫ")
        context.insert(прогрев)
        try context.save()

        // Контроль: запись в базе ЕСТЬ. Иначе «ноль дней» сказал бы
        // про пустую базу, а проверяется другое — что служебную
        // запись отбор не принимает за данные.
        #expect(try context.fetch(FetchDescriptor<LogEvent>()).count == 1)

        let однаСтрока = try context.fetch(DataPrivacyScreen.самаяРанняяПервой)
        #expect(однаСтрока.isEmpty, "служебная запись прошла отбор базы")
        #expect(Diary.daysOfData(однаСтрока) == 0)
    }
}
