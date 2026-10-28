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

    // MARK: След удалённой записи — СНЯТ 08.10.2026, решение Виктории
    //
    // Здесь стояли четыре теста на `DeletedTrace`: след «до конца дня».
    // Модуль удалён вместе с ними, и причина важнее самого удаления.
    //
    // Правило «до конца дня» пришло из `Togo ФИНАЛ v2` и **было
    // отменено живым использованием** — об этом написано там, где
    // след работает на самом деле (`Diary.onDayWithTraces`,
    // `Diary.swift:19-23`):
    //
    //     «След живёт ровно столько, сколько живёт отмена, — пять
    //      секунд. Раньше зачёркнутая строка оставалась до конца дня,
    //      и удалённое висело в ленте наравне с настоящим. Человек
    //      не нашёл, где поправить граммы, удалил запись и записал
    //      заново — а в ленте осталось и то и другое.»
    //
    // То есть след НЕ «не подключён»: он жив, его рисует
    // `DayTimeline.swift:146`, зовут из `TodayScreen.swift:317`.
    // Мёртв был только `DeletedTrace` — реализация отменённого окна.
    //
    // > **Зелёный тест без места вызова означает две разные вещи,
    // > и снаружи они неразличимы: «не доделали» и «решили
    // > не делать».** Здесь было второе, и именно поэтому модуль
    // > удалён, а не подключён: пока он лежал покрытым тестами,
    // > следующий читал его как недоделку — и подключение вернуло бы
    // > дефект, уже найденный на живых данных.
    //
    // Решение «пять секунд, а не до конца дня» — Виктории, через
    // менеджера смены. Модуль и тесты восстанавливаются из git
    // одной командой, если решение переменится.

    // Матрица навыка СНЯТА 28.10.2026 вместе с `SkillMatrix.swift`:
    // занятия и перенос навыка удалены по решению Виктории. Пять
    // тестов про клетки, места и участников ушли с предметом.
    //
    // Остальные тесты этого набора к занятиям отношения не имеют
    // (окно дозы, начало и конец эпизода, акцент темы) и оставлены
    // без правок.

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

    // MARK: Конец эпизода

    @Test("Нажатие «закончился» сильнее тишины: эпизод не оживает от свежего инцидента")
    func declaredEndBeatsQuiet() {
        let сейчас = Date()
        let инцидентЧасНазад = сейчас.addingTimeInterval(-3600)
        let объявлен = сейчас.addingTimeInterval(-60)

        // Без объявления эпизод активен — инцидент час назад.
        #expect(EpisodeLifetime.isActive(lastIncidentAt: инцидентЧасНазад, endedAt: nil, now: сейчас))
        // С объявлением — нет, хотя инцидент тот же. Порядок проверок
        // и есть правило: иначе нажатие ничего не значило бы.
        #expect(!EpisodeLifetime.isActive(lastIncidentAt: инцидентЧасНазад, endedAt: объявлен, now: сейчас))
        #expect(EpisodeLifetime.end(lastIncidentAt: инцидентЧасНазад, endedAt: объявлен, now: сейчас)
                == .declared(at: объявлен))
    }

    @Test("Тишина — сетка, а не правило: двое суток без инцидентов гасят эпизод сами")
    func quietPeriodIsTheSafetyNet() {
        let сейчас = Date()
        let давно = сейчас.addingTimeInterval(-EpisodeLifetime.quietPeriod - 60)
        let недавно = сейчас.addingTimeInterval(-EpisodeLifetime.quietPeriod + 60)

        #expect(!EpisodeLifetime.isActive(lastIncidentAt: давно, endedAt: nil, now: сейчас))
        #expect(EpisodeLifetime.end(lastIncidentAt: давно, endedAt: nil, now: сейчас) == .quiet(since: давно))
        // И обратный край: за минуту до порога эпизод ещё жив. Без этой
        // половины правило выполнялось бы и при отсутствии предмета.
        #expect(EpisodeLifetime.isActive(lastIncidentAt: недавно, endedAt: nil, now: сейчас))
        #expect(EpisodeLifetime.end(lastIncidentAt: недавно, endedAt: nil, now: сейчас) == nil)
    }

    @Test("Кнопку «закончился» не показываем у законченного эпизода")
    func endButtonHiddenWhenAlreadyOver() {
        let сейчас = Date()
        let инцидентЧасНазад = сейчас.addingTimeInterval(-3600)
        let давно = сейчас.addingTimeInterval(-EpisodeLifetime.quietPeriod - 60)

        #expect(EpisodeLifetime.canDeclareEnd(lastIncidentAt: инцидентЧасНазад, endedAt: nil, now: сейчас))
        // Уже объявлен — кнопки нет: иначе однажды покажут кнопку,
        // которая ничего не делает. У Togo это уже было с удалением
        // собаки, обещанным текстом и не существовавшим.
        #expect(!EpisodeLifetime.canDeclareEnd(lastIncidentAt: инцидентЧасНазад,
                                               endedAt: сейчас.addingTimeInterval(-60), now: сейчас))
        // Затих сам — тоже нет: заканчивать нечего.
        #expect(!EpisodeLifetime.canDeclareEnd(lastIncidentAt: давно, endedAt: nil, now: сейчас))
    }

    @Test("Причина конца различается: «закончился» и «затих сам» — разные новости")
    func endReasonsAreDistinguished() {
        let сейчас = Date()
        let давно = сейчас.addingTimeInterval(-EpisodeLifetime.quietPeriod - 60)
        let объявлен = сейчас.addingTimeInterval(-60)
        let declared = EpisodeLifetime.end(lastIncidentAt: сейчас.addingTimeInterval(-3600),
                                           endedAt: объявлен, now: сейчас)
        let quiet = EpisodeLifetime.end(lastIncidentAt: давно, endedAt: nil, now: сейчас)
        #expect(declared != quiet)
        // Одним текстом их покрывать нельзя: у Togo ступень отката
        // iCloud говорила одним текстом на три причины, и совет в нём
        // двум из трёх не помогал ничем.
        if case .declared = declared {} else { Issue.record("ожидался объявленный конец") }
        if case .quiet = quiet {} else { Issue.record("ожидался конец по тишине") }
    }

    @Test("Набору было что проверять: домен финала v2")
    func suiteHadSomethingToCheck() {
        // Первой строкой у любой группы — проверка, что предмет есть.
        // Без неё остальные тесты зеленели бы на пустых типах.
        #expect(EpisodeTrigger.looseCount == 3)
        #expect(EpisodeTrigger.window == 24 * 3600)
    }
}
