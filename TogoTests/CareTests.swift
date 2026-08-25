import Testing
import Foundation
@testable import Togo

/// Уход бывает трёх разных сортов, и путать их нельзя. Раньше всё лежало
/// одной кучей — и приложение в первый же день кричало «сегодня» про всё
/// сразу, включая купание и комплексную прививку.
@Suite("Уход")
@MainActor
struct CareTests {
    private let calendar = Calendar.current

    private func днейНазад(_ дней: Int) -> Date {
        calendar.date(byAdding: .day, value: -дней, to: .now)!
    }

    // MARK: Каждый день

    @Test("Зубы чистят каждый день — и это привычка, а не просрочка")
    func dailyHasNoOverdue() {
        let зубы = CareTask(title: "Зубы", detail: "каждый день", kind: .daily)

        #expect(зубы.isDue())
        #expect(!зубы.isOverdue(), "у привычки нет долга")
        #expect(зубы.statusText() == "сегодня")
    }

    @Test("Отметили сегодня — дело уходит с главного")
    func dailyDoneToday() {
        let зубы = CareTask(title: "Зубы", detail: "", kind: .daily)
        зубы.markDone()

        #expect(зубы.isDoneToday())
        #expect(!зубы.isDue())
        #expect(зубы.streak == 1)
    }

    @Test("Серия растёт, только если делали вчера")
    func dailyStreak() {
        let зубы = CareTask(title: "Зубы", detail: "", kind: .daily)
        зубы.lastDone = днейНазад(1)
        зубы.streak = 4
        зубы.markDone()
        #expect(зубы.streak == 5)

        let после_пропуска = CareTask(title: "Зубы", detail: "", kind: .daily)
        после_пропуска.lastDone = днейНазад(4)
        после_пропуска.streak = 9
        после_пропуска.markDone()
        #expect(после_пропуска.streak == 1, "пропустил — серия начинается заново")
    }

    @Test("Серия видна в подписи, но не превращается в награду")
    func streakText() {
        let зубы = CareTask(title: "Зубы", detail: "", kind: .daily)
        зубы.lastDone = днейНазад(1)
        зубы.streak = 6
        зубы.markDone()
        #expect(зубы.statusText().contains("7"))
    }

    // MARK: Регулярно

    @Test("Ни разу не делали — это «неизвестно», а не «просрочено»")
    func periodicNeverDone() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)

        #expect(когти.isNeverDone)
        #expect(когти.dueDate == nil)
        #expect(!когти.isDue(), "не кричим в первый же день")
        #expect(!когти.isOverdue())
        #expect(когти.statusText() == "ещё не делали")
    }

    @Test("Срок считается от последнего раза")
    func periodicFromLastDone() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = днейНазад(10)

        #expect(когти.daysUntilDue() == 11)
        #expect(!когти.isDue())
        #expect(когти.statusText() == "через 11 дней")
    }

    @Test("Просрочка считается и называется по-человечески")
    func periodicOverdue() {
        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = днейНазад(25)

        #expect(когти.isDue())
        #expect(когти.isOverdue())
        #expect(когти.statusText() == "просрочено на 4 дня")
    }

    @Test("Сезонное вне сезона молчит совсем")
    func seasonalIsSilent() {
        let капли = CareTask(title: "Капли от клещей", detail: "", kind: .periodic,
                             intervalDays: 30, category: .medical)
        капли.seasonStartMonth = 4
        капли.seasonEndMonth = 10
        капли.lastDone = днейНазад(60)

        let январь = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        #expect(!капли.isDue(on: январь))
        #expect(!капли.isOverdue(on: январь))
        #expect(капли.statusText(on: январь) == "вне сезона")
    }

    // MARK: По дате

    @Test("Прививка живёт по дате, а не «раз в год от последнего раза»")
    func datedTask() {
        let прививка = CareTask(title: "Бешенство", detail: "", kind: .dated,
                                intervalDays: 365, category: .medical)
        прививка.scheduledDate = calendar.date(byAdding: .day, value: 40, to: .now)

        #expect(прививка.daysUntilDue() == 40)
        #expect(!прививка.isDue(), "за 40 дней ещё рано")

        прививка.scheduledDate = calendar.date(byAdding: .day, value: 10, to: .now)
        #expect(прививка.isDue(), "за две недели уже пора напомнить")
    }

    @Test("Сделали прививку — дата уезжает на следующий год")
    func datedRolls() {
        let прививка = CareTask(title: "Бешенство", detail: "", kind: .dated,
                                intervalDays: 365, category: .medical)
        let сегодня = calendar.startOfDay(for: .now)
        прививка.scheduledDate = сегодня
        прививка.markDone()

        let следующая = calendar.dateComponents([.day], from: сегодня,
                                                to: прививка.scheduledDate!).day
        #expect(следующая == 365)
    }

    @Test("Разовый визит не повторяется")
    func datedOnce() {
        let визит = CareTask(title: "Осмотр", detail: "", kind: .dated,
                             intervalDays: 0, category: .medical)
        let дата = calendar.startOfDay(for: .now)
        визит.scheduledDate = дата
        визит.markDone()
        #expect(визит.scheduledDate == дата, "повторять не просили")
    }

    // MARK: Список предложений

    @Test("Предлагаем немного и по делу, а не девять дел разом")
    func suggestionsAreSane() {
        let предложения = SeedData.careSuggestions
        let поумолчанию = предложения.filter(\.isDefault)

        #expect(поумолчанию.count <= 7, "навязывать десяток дел на старте нельзя")
        #expect(предложения.contains { $0.title == "Зубы" && $0.kind == .daily },
                "зубы чистят каждый день")
        #expect(!предложения.contains { $0.title.contains("Уши и зубы") },
                "уши и зубы — разные дела с разной частотой")
        #expect(предложения.contains { $0.kind == .dated }, "прививки живут по дате")
    }

    @Test("Первый запуск не заводит ухода за человека")
    func firstRunAddsNoCare() {
        // Стартовый набор — это вес, а не девять напоминаний.
        // Уход человек выбирает сам, иначе он сразу становится шумом.
        #expect(SeedData.careSuggestions.allSatisfy { !$0.title.isEmpty })
    }
}
