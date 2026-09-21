import Testing
import Foundation
import SwiftData
@testable import Togo

/// Системы, которые были написаны и не вызывались ниоткуда.
///
/// Отдельный набор, потому что это особый сорт ошибки: код есть, экраны
/// есть, тесты на сам код проходят — а в живом приложении не срабатывает
/// ничего. Ловится только вопросом «кто это вызывает».
@Suite("Непокрытая логика")
@MainActor
struct DeadLogicTests {
    private func контекст() -> ModelContext {
        ModelContext(Persistence.container())
    }

    // MARK: Утренняя сводка

    @Test("В сводку попадают дела на завтра, а не пустота")
    func briefHasLines() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        let когти = CareTask(title: "Когти", detail: "", kind: .periodic, intervalDays: 21)
        когти.lastDone = Calendar.current.date(byAdding: .day, value: -21, to: .now)
        когти.dog = dog
        context.insert(когти)

        let строки = ReminderScheduler.briefLines(dog: dog)
        #expect(строки.count == 1)
        #expect(строки[0].contains("Когти"))
    }

    @Test("Отложенное дважды подсвечивается в сводке, но не становится тревогой")
    func snoozedIsMarked() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        let дело = CareTask(title: "Купать", detail: "", kind: .periodic, intervalDays: 60)
        дело.lastDone = Calendar.current.date(byAdding: .day, value: -60, to: .now)
        дело.snoozeCount = 2
        дело.dog = dog
        context.insert(дело)

        #expect(ReminderScheduler.briefLines(dog: dog)[0].contains("откладывали"))
    }

    @Test("Ежедневное в сводку не сыплется каждый день без причины")
    func briefIsShort() {
        let context = контекст()
        let dog = Dog(name: "Стич", weightKg: 4.73)
        context.insert(dog)

        for index in 0..<9 {
            let дело = CareTask(title: "Дело \(index)", detail: "", kind: .periodic, intervalDays: 7)
            дело.lastDone = Calendar.current.date(byAdding: .day, value: -8, to: .now)
            дело.dog = dog
            context.insert(дело)
        }

        #expect(ReminderScheduler.briefLines(dog: dog).count <= 4,
                "один пуш, а не список из девяти строк")
    }

    @Test("Без собаки сводка пустая и ничего не шлёт")
    func briefWithoutDog() {
        #expect(ReminderScheduler.briefLines(dog: nil).isEmpty)
    }

    // MARK: Как попросил

    @Test("Лай, вытесняющий спокойный сигнал, виден в цифрах")
    func barkingIsDetected() {
        var события: [LogEvent] = []
        let сейчас = Date()

        // Две недели назад просил спокойно.
        for index in 0..<9 {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(9 + index) * 24 * 3600),
                                 authorName: "Виктория")
            выход.askSignal = .satAtDoor
            события.append(выход)
        }
        // На этой неделе в основном лает.
        for index in 0..<9 {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(index) * 8 * 3600),
                                 authorName: "Виктория")
            выход.askSignal = index < 7 ? .barked : .satAtDoor
            события.append(выход)
        }

        #expect(Diary.barkingIsDisplacingCalm(события, now: сейчас),
                "ровно тот случай, ради которого этот вопрос и задаётся")
    }

    @Test("Пока сигналов мало, выводов не делаем")
    func fewSignalsMeanSilence() {
        let сейчас = Date()
        let выход = LogEvent(kind: .outing, date: сейчас, authorName: "Виктория")
        выход.askSignal = .barked

        #expect(!Diary.barkingIsDisplacingCalm([выход], now: сейчас))
    }

    @Test("Спокойные и беспокойные сигналы считаются раздельно")
    func tallySplitsSignals() {
        let сейчас = Date()
        var события: [LogEvent] = []
        for (index, сигнал) in [AskSignal.satAtDoor, .cameAndLooked, .barked, .scratchedDoor].enumerated() {
            let выход = LogEvent(kind: .outing,
                                 date: сейчас.addingTimeInterval(-Double(index) * 3600),
                                 authorName: "Виктория")
            выход.askSignal = сигнал
            события.append(выход)
        }

        let счёт = Diary.signalTally(события, from: сейчас.addingTimeInterval(-24 * 3600), to: сейчас.addingTimeInterval(1))
        #expect(счёт.calm == 2)
        #expect(счёт.barking == 2)
        #expect(счёт.total == 4)
    }

    // MARK: Шаги обучения

    @Test("Шаг закрывается после двух удачных занятий подряд")
    func stepClosesAfterTwoGood() {
        let шаг = TrainingStep(cue: "Ко мне", place: "Дома", person: "Виктория", distanceMeters: 2)
        #expect(!шаг.isClosed)
        шаг.consecutiveGoodSessions = 2
        #expect(шаг.isClosed)
    }

    @Test("Занятие с отказом от еды прогресс не двигает")
    func refusedFoodVoidsProgress() {
        let занятие = TrainingSession(cue: "Ко мне", place: "Дома",
                                      person: "Виктория", distanceMeters: 2)
        занятие.attempts = 5
        занятие.successes = 5
        занятие.observations = [.refusedFood]

        #expect(занятие.isVoided)
        #expect(занятие.isGoodSession, "само по себе занятие удачное")
        // Но экран не засчитает его в прогресс: countsTowardProgress
        // выставляется по наблюдениям и времени.
    }

    // MARK: Беру на себя

    @Test("«Беру на себя» живёт 45 минут и не даёт дать дозу дважды")
    func claimProtectsFromDoubleDose() {
        let доза = DoseRecord(scheduledAt: Date())
        let взяли = Date()
        доза.claimedBy = "Тео"
        доза.claimedAt = взяли

        #expect(доза.claimIsActive(at: взяли.addingTimeInterval(40 * 60)))
        #expect(!доза.claimIsActive(at: взяли.addingTimeInterval(46 * 60)),
                "срок истёк — эскалация идёт дальше")
    }

    @Test("Эскалация не трогает того, кто уже отметил")
    func givenDoseIsQuiet() {
        let время = Date()
        let доза = DoseRecord(scheduledAt: время)
        доза.givenAt = время
        #expect(доза.escalationStage(at: время.addingTimeInterval(2 * 3600)) == 0)
    }

    // MARK: Число, напечатанное дважды

    /// `Fmt.plural` возвращает число **вместе** со словом: `plural(5, …)`
    /// это «5 напоминаний», а не «напоминаний». Кто ставит число перед
    /// ним, печатает его дважды.
    ///
    /// 21.09.2026 на телефоне это выглядело как «**5 5** напоминаний ждут
    /// даты» и «**3 3** выхода за день». Два места, и оба — продуктовые
    /// экраны. Третье (`VetSummaryScreen`) обходилось
    /// `replacingOccurrences`, то есть про ловушку знали и лечили её
    /// по месту вместо того, чтобы закрыть.
    ///
    /// Проверка лексическая — и здесь это правильный инструмент: вопрос
    /// «стоит ли в строке число прямо перед вызовом» решается текстом,
    /// а не вёрсткой.
    @Test("Число не печатается дважды рядом с Fmt.plural")
    func числоНеПечатаетсяДважды() {
        let ловушка = try! NSRegularExpression(
            pattern: #"\\\([A-Za-z0-9_.]+\)\s*\\\(Fmt\.(plural|days|outings)\("#
        )
        var находки: [String] = []
        for путь in Self.исходникиПриложения() {
            guard let текст = try? String(contentsOfFile: путь, encoding: .utf8) else { continue }
            for (номер, строка) in текст.components(separatedBy: .newlines).enumerated() {
                let диапазон = NSRange(строка.startIndex..., in: строка)
                guard ловушка.firstMatch(in: строка, range: диапазон) != nil else { continue }
                // `replacingOccurrences` — известный обход, он число убирает.
                guard !строка.contains("replacingOccurrences") else { continue }
                находки.append("\((путь as NSString).lastPathComponent):\(номер + 1)")
            }
        }
        #expect(находки.isEmpty, "число напечатается дважды: \(находки)")
    }

    // MARK: Тишина в журнале — не факт о собаке

    /// 21.09.2026 после восемнадцати дней без отметок главный экран
    /// показал «**434 ч назад · на улице были**». Приложение сказало
    /// о собаке то, чего не знало: оно знало не про собаку, а про то,
    /// что записей нет с 3 сентября.
    ///
    /// Та же форма дефекта, что и во всём остальном проекте —
    /// отсутствие записи выдано за отсутствие события.
    @Test("За сутками тишины экран говорит про записи, а не про собаку")
    func тишинаНеВыдаётсяЗаЧислоЧасов() {
        let последнийВыход = Date(timeIntervalSince1970: 1_788_000_000)

        // Восемнадцать дней — ровно тот случай, что был на телефоне.
        #expect(
            TodayHero.silence(indoors: 18 * 24 * 3600, lastOutingEndedAt: последнийВыход)
                == последнийВыход,
            "после восемнадцати дней тишины экран снова напечатает число часов"
        )

        // Сутки — сам потолок, и он включительно.
        #expect(
            TodayHero.silence(indoors: TodayHero.silenceCeiling,
                              lastOutingEndedAt: последнийВыход) != nil
        )

        // До потолка вопрос «давно ли гуляли» ещё имеет смысл,
        // и число часов — правильный ответ на него.
        #expect(
            TodayHero.silence(indoors: 5 * 3600, lastOutingEndedAt: последнийВыход) == nil,
            "пять часов дома — это ответ на вопрос экрана, а не тишина"
        )

        // Выходов не записано ни одного: сказать «записей нет с такого-то»
        // не из чего, и экран остаётся при «сегодня ещё не выходили».
        #expect(TodayHero.silence(indoors: 18 * 24 * 3600, lastOutingEndedAt: nil) == nil)
        #expect(TodayHero.silence(indoors: nil, lastOutingEndedAt: последнийВыход) == nil)
    }

    // MARK: Проводка — кто это вызывает

    /// **Главный тест набора, и до 21.09.2026 его здесь не было.**
    ///
    /// Всё, что выше, зовёт функции напрямую и о местах вызова ничего не
    /// знает. Убери из `TodayScreen` строку с `AskSignalCard` — карточка
    /// перестанет существовать для человека, а набор останется зелёным.
    /// То есть ошибка, ради которой набор и заведён («код есть, экраны
    /// есть, а в живом приложении не срабатывает ничего»), им же и не
    /// ловилась: он проверял, что функция считает правильно, а не что
    /// её кто-то спрашивает.
    ///
    /// Здесь записана **проводка каждой системы до экрана**. Звено между
    /// вычислением и экраном пропало — тест красный и называет, какое.
    ///
    /// Цепочка, а не одно упоминание, потому что путь бывает в два шага:
    /// `briefLines` зовётся из `scheduleBrief` в том же файле, и только
    /// `scheduleBrief` виден экрану настроек. Проверка «символ упомянут
    /// где-то ещё» такую проводку не описывает.
    @Test("Каждая система этого набора доведена до экрана")
    func каждаяСистемаДоведенаДоЭкрана() {
        let цепочки: [(система: String, звенья: [String])] = [
            ("утренняя сводка",          ["briefLines", "scheduleBrief"]),
            ("карточка сигналов",        ["signalTally", "AskSignalCard"]),
            ("лай вытесняет спокойное",  ["barkingIsDisplacingCalm", "AskSignalCard"]),
            ("шаг закрывается",          ["isClosed"]),
            ("занятие аннулируется",     ["isVoided"]),
            ("удачное занятие",          ["isGoodSession"]),
            ("«беру на себя»",           ["claimIsActive"]),
            ("эскалация дозы",           ["escalationStage"]),
        ]

        let исходники = Self.исходникиПриложения()
        #expect(!исходники.isEmpty, "исходники приложения не нашлись — проверять нечего")

        for цепочка in цепочки {
            for (номер, звено) in цепочка.звенья.enumerated() {
                let (всего, чужиеФайлы) = Self.упоминания(звена: звено, в: исходники)

                // Объявление плюс хотя бы одно обращение. Ровно одно
                // упоминание значит, что символ существует и не нужен никому.
                #expect(
                    всего >= 2,
                    "«\(цепочка.система)»: \(звено) объявлен и не вызывается ниоткуда"
                )

                // Последнее звено обязано дотянуться до слоя экранов,
                // и не собственным файлом: `AskSignalCard` сам лежит
                // в `Features/`, и без этой оговорки удаление вызова
                // из `TodayScreen` осталось бы незамеченным.
                if номер == цепочка.звенья.count - 1 {
                    #expect(
                        чужиеФайлы.contains(where: Self.этоЭкран),
                        "«\(цепочка.система)»: \(звено) есть в коде, но до экрана не доходит — ни один экран и ни один виджет его не вызывает"
                    )
                }
            }
        }
    }

    /// Все `.swift` приложения: экраны (`Togo`), домен и модели
    /// (`TogoShared`) и виджеты (`TogoWidgets`).
    ///
    /// Тесты сюда не входят намеренно: вызов из теста проводкой не
    /// является — ровно с этой подмены беда и началась.
    ///
    /// Три корня, а не один: сперва здесь стоял только `Togo`, и тест
    /// объявил мёртвыми `barkingIsDisplacingCalm`, `isVoided`
    /// и `escalationStage` — все три просто объявлены в `TogoShared`.
    /// Сторож, который врёт в свою сторону, не лучше бумажного.
    static func исходникиПриложения() -> [String] {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TogoTests
            .deletingLastPathComponent()   // корень репозитория
        var пути: [String] = []
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            guard let обход = FileManager.default.enumerator(
                at: корень.appendingPathComponent(каталог), includingPropertiesForKeys: nil
            ) else { continue }
            for случай in обход {
                guard let url = случай as? URL, url.pathExtension == "swift" else { continue }
                пути.append(url.path)
            }
        }
        return пути
    }

    /// Слой, который видит человек: экраны приложения и виджеты.
    private static func этоЭкран(_ путь: String) -> Bool {
        путь.contains("/Features/") || путь.contains("/TogoWidgets/")
    }

    /// Сколько раз символ встречается во всех исходниках и в каких файлах,
    /// кроме того, где он объявлен.
    private static func упоминания(
        звена символ: String, в исходники: [String]
    ) -> (всего: Int, чужиеФайлы: [String]) {
        let объявление = try? NSRegularExpression(
            pattern: "(func|var|let|struct|enum|class)\\s+\(символ)\\b"
        )
        var всего = 0
        var чужие: [String] = []
        for путь in исходники {
            guard let текст = try? String(contentsOfFile: путь, encoding: .utf8),
                  текст.contains(символ) else { continue }
            всего += текст.components(separatedBy: символ).count - 1
            let диапазон = NSRange(текст.startIndex..., in: текст)
            let этоОбъявление = объявление?.firstMatch(in: текст, range: диапазон) != nil
            if !этоОбъявление { чужие.append(путь) }
        }
        return (всего, чужие)
    }
}

/// Манифест приватности против того, что код правда делает.
///
/// С 1 мая 2024 Apple требует объявлять «API с обязательной причиной»,
/// и код причины — не формальность: **CA92.1** разрешает только своё
/// хранилище и прямо НЕ разрешает писать то, что доступно другим
/// приложениям и расширениям; **1C8F.1** — это общая группа.
///
/// 21.09.2026 у Того стоял CA92.1, а `ActiveSessionStore` и `FamilySync`
/// пишут в `UserDefaults(suiteName: "group.app.togo.diary")`, откуда
/// читают виджет и Live Activity. Объявлено было ровно то, что делать
/// нельзя. Неверная причина хуже отсутствующей: отсутствующую ловит
/// автоматика Apple письмом ITMS-91053, а неверная проходит молча
/// и всплывает на ревью.
@Suite("Манифест приватности")
struct PrivacyManifestTests {

    private var корень: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func причины(_ путь: String) -> [String] {
        let url = корень.appendingPathComponent(путь)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any],
              let types = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        else { return [] }
        return types
            .filter { $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults" }
            .flatMap { $0["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [] }
    }

    @Test("Код пишет в общую группу — манифест обязан объявлять 1C8F.1")
    func общаяГруппаОбъявлена() {
        // Сначала измеряем сам факт: пользуется ли код общей группой.
        let исходники = DeadLogicTests.исходникиПриложения()
        let общая = исходники.contains { путь in
            (try? String(contentsOfFile: путь, encoding: .utf8))?
                .contains("UserDefaults(suiteName:") ?? false
        }
        #expect(общая, "код перестал пользоваться общей группой — правило пора пересмотреть")

        for манифест in ["Togo/Resources/PrivacyInfo.xcprivacy",
                         "TogoWidgets/PrivacyInfo.xcprivacy"] {
            let коды = причины(манифест)
            #expect(коды.contains("1C8F.1"), "\(манифест): общая группа не объявлена")
            #expect(!коды.contains("CA92.1"),
                    "\(манифест): CA92.1 прямо не разрешает то, что делает код — писать в общую группу")
        }
    }
}
