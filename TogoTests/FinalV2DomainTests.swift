import Testing
import Foundation
@testable import Togo

/// Логика под экраны нового дизайна (`Togo ФИНАЛ v2`, окт 2026).
///
/// Все проверки написаны **от обратного**, то есть от утверждения,
/// которое дефект нарушит. У Togo и Kvit записано, чем кончается
/// обратное: тест «уходят не все» проходил и при нуле, потому что ноль
/// это тоже «не все». Поэтому ниже каждое правило проверяется парой —
/// «обязано сработать» и «обязано НЕ сработать», — а не одним краем.
@Suite("ФИНАЛ v2 · логика под новые экраны")
struct FinalV2DomainTests {

    // MARK: Прайминг уведомлений

    @Test("Своё окно появляется ровно на первой дозе и только если система не спрашивала")
    func primingOnlyAtFirstDose() {
        let пусто = NotificationPriming.Memory()
        #expect(NotificationPriming.shouldPrime(occasion: .firstDose, system: .notAsked, memory: пусто))
        // Повод не тот — молчим. Без этой половины правило выполнялось бы
        // всегда, когда система не спрашивала, то есть на первом запуске.
        #expect(!NotificationPriming.shouldPrime(occasion: .other, system: .notAsked, memory: пусто))
    }

    @Test("После отказа не спрашиваем больше никогда — даже на первой дозе")
    func neverAsksAfterDecline() {
        let отказ = NotificationPriming.remember(NotificationPriming.Memory(), accepted: false)
        #expect(отказ.didDecline)
        #expect(!NotificationPriming.shouldPrime(occasion: .firstDose, system: .notAsked, memory: отказ))
    }

    @Test("Согласие тоже закрывает вопрос: окно показывали, второй раз не показываем")
    func doesNotRepeatAfterAccept() {
        let согласие = NotificationPriming.remember(NotificationPriming.Memory(), accepted: true)
        #expect(!согласие.didDecline)
        #expect(согласие.didPrime)
        #expect(!NotificationPriming.shouldPrime(occasion: .firstDose, system: .notAsked, memory: согласие))
    }

    @Test("Системный отказ уводит в настройки, остальные состояния — нет")
    func deniedNeedsSettings() {
        #expect(NotificationPriming.needsSystemSettings(system: .denied))
        #expect(!NotificationPriming.needsSystemSettings(system: .notAsked))
        #expect(!NotificationPriming.needsSystemSettings(system: .granted))
    }

    // MARK: След удалённой записи

    @Test("Удалённая сегодня видна зачёркнутой, удалённая вчера — не видна")
    func traceLivesUntilEndOfDay() {
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = TimeZone(identifier: "Europe/Paris")!
        let сейчас = Date(timeIntervalSince1970: 1_791_000_000)
        let сегодняРаньше = сейчас.addingTimeInterval(-3 * 3600)
        let вчера = календарь.startOfDay(for: сейчас).addingTimeInterval(-3600)

        #expect(DeletedTrace.visibility(deletedAt: сегодняРаньше, now: сейчас, calendar: календарь) == .struckThrough)
        #expect(DeletedTrace.visibility(deletedAt: вчера, now: сейчас, calendar: календарь) == .gone)
    }

    @Test("Срок жизни следа — начало следующих суток, а не сутки с удаления")
    func traceDiesAtMidnightNotAfter24h() {
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = TimeZone(identifier: "Europe/Paris")!
        let сейчас = Date(timeIntervalSince1970: 1_791_000_000)
        let полночь = календарь.startOfDay(for: сейчас)
        let удалено = полночь.addingTimeInterval(23 * 3600 + 50 * 60)

        let исчезнет = DeletedTrace.disappearsAt(deletedAt: удалено, now: удалено, calendar: календарь)
        // Запись, удалённая в 23:50, обязана пропасть через десять минут,
        // а не висеть зачёркнутой весь следующий день.
        #expect(исчезнет == полночь.addingTimeInterval(24 * 3600))
        if let исчезнет {
            #expect(исчезнет.timeIntervalSince(удалено) < 3600)
        }
    }

    @Test("У невидимого следа не спрашивают, когда он исчезнет")
    func goneTraceHasNoDeadline() {
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = TimeZone(identifier: "Europe/Paris")!
        let сейчас = Date(timeIntervalSince1970: 1_791_000_000)
        let вчера = календарь.startOfDay(for: сейчас).addingTimeInterval(-3600)
        #expect(DeletedTrace.disappearsAt(deletedAt: вчера, now: сейчас, calendar: календарь) == nil)
    }

    @Test("След не входит в счёт дня")
    func traceNeverCounts() {
        #expect(DeletedTrace.countsTowardDayTotals == false)
    }

    // MARK: Матрица навыка

    /// Один участник, чтобы клетки не расходились по столбцам.
    private static let мама = UUID()
    private static let аня = UUID()

    private func попытки(_ place: SkillMatrix.Place,
                         _ member: UUID,
                         успехов: Int,
                         всего: Int) -> [SkillMatrix.Attempt] {
        (0..<всего).map { index in
            SkillMatrix.Attempt(place: place,
                                memberID: member,
                                succeeded: index < успехов,
                                date: Date().addingTimeInterval(-Double(index) * 3600))
        }
    }

    @Test("Матрица различает место: дома получается, на улице нет")
    func matrixSeparatesPlaces() {
        let список = попытки(.home, Self.мама, успехов: 5, всего: 5)
            + попытки(.street, Self.мама, успехов: 1, всего: 5)
        let клетки = SkillMatrix.cells(список)

        let дом = клетки.first { $0.place == .home }
        let улица = клетки.first { $0.place == .street }
        #expect(дом?.status == .works)
        #expect(улица?.status == .learning)
        // Ради этого матрица и существует: сводное число по тем же
        // данным — 6 из 10 — не сказало бы ни про дом, ни про улицу.
        #expect(SkillProgress.status(successes: 6, attempts: 10) == .learning)
    }

    @Test("Матрица различает участника на одном и том же месте")
    func matrixSeparatesMembers() {
        let список = попытки(.yard, Self.мама, успехов: 5, всего: 5)
            + попытки(.yard, Self.аня, успехов: 0, всего: 5)
        let клетки = SkillMatrix.cells(список).filter { $0.place == .yard }
        #expect(клетки.count == 2)
        #expect(клетки.first { $0.memberID == Self.мама }?.status == .works)
        #expect(клетки.first { $0.memberID == Self.аня }?.status == .learning)
    }

    @Test("Клетка без попыток не заводится вовсе — «не пробовали» не равно «ноль из нуля»")
    func emptyCellIsAbsent() {
        let клетки = SkillMatrix.cells(попытки(.home, Self.мама, успехов: 1, всего: 1))
        #expect(клетки.count == 1)
        #expect(клетки.allSatisfy { $0.attempts > 0 })
        #expect(SkillMatrix.cells([]).isEmpty)
        // Пустую матрицу показывать нельзя: четырнадцать «—» читаются
        // как поломка, а не как пустое состояние.
        #expect(!SkillMatrix.hasAnythingToShow([]))
    }

    @Test("Окно обрезает прошлое: научившаяся собака не висит в «учится» из-за старых попыток")
    func windowCutsOldAttempts() {
        // Двадцать попыток: десять свежих удачных, десять старых
        // неудачных. Без окна — 10 из 20, то есть «учится» навсегда.
        let свежие = (0..<10).map { index in
            SkillMatrix.Attempt(place: .street, memberID: Self.мама, succeeded: true,
                                date: Date().addingTimeInterval(-Double(index) * 3600))
        }
        let старые = (0..<10).map { index in
            SkillMatrix.Attempt(place: .street, memberID: Self.мама, succeeded: false,
                                date: Date().addingTimeInterval(-Double(index + 100) * 3600))
        }
        let клетка = SkillMatrix.cells(старые + свежие).first { $0.place == .street }
        #expect(клетка?.attempts == SkillMatrix.window)
        #expect(клетка?.successes == 10)
        #expect(клетка?.status == .works)
    }

    @Test("Отрабатывать предлагается самое простое из непройденных, а не самое трудное")
    func practisesEasiestUnfinishedFirst() {
        let список = попытки(.home, Self.мама, успехов: 5, всего: 5)      // получается
            + попытки(.entrance, Self.мама, успехов: 1, всего: 5)         // учится
            + попытки(.street, Self.мама, успехов: 0, всего: 5)           // учится
        #expect(SkillMatrix.nextPlaceToPractise(SkillMatrix.cells(список)) == .entrance)
        // Когда непройденных нет — ответа нет, и это не «всё хорошо»,
        // а отсутствие предмета. Решает тот, кто спрашивает.
        let всёПолучается = попытки(.home, Self.мама, успехов: 5, всего: 5)
        #expect(SkillMatrix.nextPlaceToPractise(SkillMatrix.cells(всёПолучается)) == nil)
    }

    // MARK: Начало эпизода

    private func наблюдение(жидкий: Bool, кровь: Bool = false, часовНазад: Double) -> EpisodeTrigger.Observation {
        EpisodeTrigger.Observation(date: Date().addingTimeInterval(-часовНазад * 3600),
                                   isLooseStool: жидкий,
                                   hasBlood: кровь)
    }

    @Test("Третий жидкий за сутки начинает эпизод, второй — нет")
    func thirdLooseStarts() {
        let два = [наблюдение(жидкий: true, часовНазад: 1), наблюдение(жидкий: true, часовНазад: 3)]
        #expect(EpisodeTrigger.reasonToStart(два) == nil)
        #expect(EpisodeTrigger.looseUntilStart(два) == 1)

        let три = два + [наблюдение(жидкий: true, часовНазад: 5)]
        #expect(EpisodeTrigger.reasonToStart(три) == .thirdLoose(count: 3))
        #expect(EpisodeTrigger.looseUntilStart(три) == 0)
    }

    @Test("Кровь начинает эпизод с первого раза, без счёта жидких")
    func bloodStartsImmediately() {
        // Один жидкий с кровью: по счёту жидких эпизод бы не начался.
        // Правило «или» обязано сработать здесь, иначе оно значит «и».
        let одно = [наблюдение(жидкий: true, кровь: true, часовНазад: 1)]
        #expect(EpisodeTrigger.reasonToStart(одно) == .blood)

        // И кровь без жидкого стула — тоже повод: рвота с кровью.
        let рвота = [наблюдение(жидкий: false, кровь: true, часовНазад: 1)]
        #expect(EpisodeTrigger.reasonToStart(рвота) == .blood)
    }

    @Test("Старое за окном не считается: три жидких за неделю эпизода не начинают")
    func windowExcludesOldObservations() {
        let давно = [наблюдение(жидкий: true, часовНазад: 30),
                     наблюдение(жидкий: true, часовНазад: 50),
                     наблюдение(жидкий: true, часовНазад: 90)]
        #expect(EpisodeTrigger.reasonToStart(давно) == nil)
        #expect(EpisodeTrigger.looseUntilStart(давно) == EpisodeTrigger.looseCount)
    }

    @Test("Повод различается: «третий жидкий» и «кровь» — разные новости, не один текст")
    func reasonsAreDistinguished() {
        let жидкие = (1...3).map { наблюдение(жидкий: true, часовНазад: Double($0)) }
        let сКровью = жидкие + [наблюдение(жидкий: true, кровь: true, часовНазад: 4)]
        #expect(EpisodeTrigger.reasonToStart(жидкие) != EpisodeTrigger.reasonToStart(сКровью))
        #expect(EpisodeTrigger.reasonToStart(сКровью) == .blood)
    }

    // MARK: Выбор акцента

    @Test("Акцент по умолчанию — индиго, и умолчание задано величиной, а не порядком объявления")
    func accentDefaultsToIndigo() {
        #expect(AccentChoice.fallback == .indigo)
        #expect(AccentChoice.parse(nil).choice == .indigo)
        #expect(AccentChoice.parse("").choice == .indigo)
        // Порядок `allCases` задаётся объявлением; перестановка случаев
        // не должна менять умолчание ни у кого.
        #expect(AccentChoice.fallback == AccentChoice.allCases.first)
    }

    @Test("Чужое значение откатывается к умолчанию и СООБЩАЕТ об этом")
    func unknownAccentIsReported() {
        let (выбор, чужое) = AccentChoice.parse("lime")
        #expect(выбор == .indigo)
        // Молчаливый откат неотличим от «человек выбрал индиго».
        // Лайм здесь не случаен: это прежнее поколение акцента,
        // и ровно такое значение прилетит из старых настроек.
        #expect(чужое)
        #expect(!AccentChoice.parse("indigo").wasUnknown)
    }

    @Test("Имя режима совпадает с коллекцией Figma побайтно")
    func figmaModeNamesMatch() {
        // Сверяется с `tokens/figma-variables.json` нового пакета:
        // коллекция Accent, режимы Indigo · Orange · Pink. Если режим
        // переименуют, расхождение обязано покраснеть здесь, а не
        // проявиться пустым цветом на экране.
        #expect(AccentChoice.indigo.figmaMode == "Indigo")
        #expect(AccentChoice.orange.figmaMode == "Orange")
        #expect(AccentChoice.pink.figmaMode == "Pink")
        #expect(AccentChoice.allCases.count == 3)
    }

    @Test("Набору было что проверять")
    func suiteHadSomethingToCheck() {
        // Первой строкой у любой группы — проверка, что предмет есть.
        // Без неё остальные тесты зеленели бы на пустых типах.
        #expect(SkillMatrix.Place.allCases.count == 4)
        #expect(EpisodeTrigger.looseCount == 3)
        #expect(EpisodeTrigger.window == 24 * 3600)
        #expect(SkillMatrix.window == 10)
    }
}
