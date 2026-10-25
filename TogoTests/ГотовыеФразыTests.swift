import Foundation
import Testing
@testable import Togo

/// Интент без готовой фразы — либо решение, либо пропуск, и отличить
/// их нечем, пока причина не записана.
///
/// **Повод.** Опись 24.10.2026: «`StartWalkIntent` и `FinishWalkIntent`
/// не в `TogoShortcuts` — 5 интентов из 7. Голосом не зовутся сразу
/// после установки». Довод за отсутствие нашёлся (`TogoShortcuts`,
/// голова; `DoorTagScreen` обещает человеку одну фразу «Togo: прогулка»),
/// но **механизма, который заметил бы следующий такой пропуск,
/// не было**: добавь интент — и он просто не появится в «Командах»
/// готовой фразой, молча и навсегда.
///
/// Ось — **перечисление**, а не число: «каждый объявленный в дереве
/// интент либо имеет готовую фразу, либо назван в `безГотовойФразы`
/// с причиной». Счёт «интентов семь» устарел бы в день восьмого,
/// и устарел бы молча.
///
/// ## Что этот сторож читает с диска
///
/// Исходники из `Togo`, `TogoShared`, `TogoWidgets` — путь считается
/// от `#filePath`. Значит он ломается от переноса каталогов, и ломается
/// **не на своём предмете**: поэтому деревья проверяются на наличие,
/// а число найденных файлов — порогом.
///
/// ## Почему разбор исходника здесь честен
///
/// Обычно сканирующий сторож меряет прозу. Здесь у него есть **контроль
/// из другого канала, снятый в том же замере**: `TogoShortcuts.appShortcuts`
/// — это живой код, и его длина обязана совпасть с числом разобранных
/// `intent:`. Разъехались — виноват разбор, и видно это до вывода
/// о проекте.
@Suite("Готовые фразы Siri")
struct ГотовыеФразыTests {

    // MARK: Чтение дерева

    private static var корень: URL {
        URL(fileURLWithPath: #filePath)       // TogoTests/ГотовыеФразыTests.swift
            .deletingLastPathComponent()      // TogoTests
            .deletingLastPathComponent()      // корень репозитория
    }

    private static let деревья = ["Togo", "TogoShared", "TogoWidgets"]

    /// Файл объявления готовых фраз.
    private static var файлФраз: URL {
        корень.appendingPathComponent("Togo/Intents/QuickLogIntents.swift")
    }

    /// Комментарии вырезаются ДО разбора.
    ///
    /// Иначе сторож меряет прозу: в головах этих файлов имена интентов
    /// встречаются чаще, чем в коде, — `WalkIntents.swift` называет
    /// `WalkTagIntent` в комментарии дважды, а объявляет один раз.
    static func безКомментариев(_ текст: String) -> String {
        var результат = ""
        var i = текст.startIndex
        var вБлоке = false
        var вСтроке = false
        var вЛитерале = false
        while i < текст.endIndex {
            let c = текст[i]
            let след = текст.index(after: i)
            let пара = след < текст.endIndex ? String([c, текст[след]]) : String(c)

            if вБлоке {
                if пара == "*/" { вБлоке = false; i = текст.index(after: след); continue }
                if c == "\n" { результат.append(c) }
                i = след; continue
            }
            if вСтроке {
                if c == "\n" { вСтроке = false; результат.append(c) }
                i = след; continue
            }
            if вЛитерале {
                // Внутри строкового литерала `//` и `/*` — не комментарий.
                результат.append(c)
                if c == "\"" { вЛитерале = false }
                i = след; continue
            }
            if пара == "//" { вСтроке = true; i = след; continue }
            if пара == "/*" { вБлоке = true; i = текст.index(after: след); continue }
            if c == "\"" { вЛитерале = true }
            результат.append(c)
            i = след
        }
        return результат
    }

    /// Все `.swift` трёх деревьев, уже без комментариев.
    ///
    /// Наличие дерева проверяется ДО обхода: `FileManager.enumerator(at:)`
    /// по несуществующему пути отдаёт `nil` молча — на этом
    /// `FallbackLiteralTests` четверо суток обходил несуществующий
    /// каталог.
    static func исходники() throws -> [String: String] {
        var собрано: [String: String] = [:]
        for дерево in деревья {
            let путь = корень.appendingPathComponent(дерево)
            var папка: ObjCBool = false
            let есть = FileManager.default.fileExists(atPath: путь.path, isDirectory: &папка)
            #expect(есть && папка.boolValue, """
                дерева «\(дерево)» нет на диске (\(путь.path)). Это отказ \
                инструмента, а не находка: обход молча вернул бы ноль \
                интентов и сторож был бы зелёным.
                """)
            guard есть, папка.boolValue,
                  let обход = FileManager.default.enumerator(at: путь,
                                                             includingPropertiesForKeys: nil)
            else { continue }
            for случай in обход {
                guard let url = случай as? URL, url.pathExtension == "swift" else { continue }
                собрано[url.lastPathComponent] = безКомментариев(try String(contentsOf: url, encoding: .utf8))
            }
        }
        return собрано
    }

    // MARK: Разбор

    /// Имена типов, объявленных интентами.
    ///
    /// Считается интентом любой `struct`, у которого в списке соответствий
    /// есть имя, кончающееся на `Intent`: `AppIntent`,
    /// `LiveActivityIntent`, `ControlConfigurationIntent` и что ещё
    /// заведёт Apple. Проверять по точному списку значило бы ослепнуть
    /// на новый вид в день его появления.
    static func объявленныеИнтенты(в файлы: [String: String]) -> [String: String] {
        var найдено: [String: String] = [:]
        let регулярка = try! NSRegularExpression(
            pattern: #"\bstruct\s+(\w+)\s*:\s*([^\{]{0,200}?)\{"#, options: [.dotMatchesLineSeparators])
        for (имяФайла, текст) in файлы {
            let диапазон = NSRange(текст.startIndex..., in: текст)
            for m in регулярка.matches(in: текст, range: диапазон) {
                guard let имя = Range(m.range(at: 1), in: текст),
                      let списки = Range(m.range(at: 2), in: текст) else { continue }
                let соответствия = String(текст[списки])
                    .split(whereSeparator: { ",&\n".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard соответствия.contains(where: { $0.hasSuffix("Intent") }) else { continue }
                найдено[String(текст[имя])] = имяФайла
            }
        }
        return найдено
    }

    /// Интенты, которым дана готовая фраза: `intent: X()` в `appShortcuts`.
    static func сГотовойФразой(_ текстФраз: String) -> [String] {
        let регулярка = try! NSRegularExpression(pattern: #"\bintent:\s*(\w+)\("#)
        let диапазон = NSRange(текстФраз.startIndex..., in: текстФраз)
        return регулярка.matches(in: текстФраз, range: диапазон).compactMap {
            Range($0.range(at: 1), in: текстФраз).map { r in String(текстФраз[r]) }
        }
    }

    /// Сами фразы и короткие имена — для проверки на столкновение.
    static func литералы(_ текстФраз: String, после ключ: String) -> [String] {
        let регулярка = try! NSRegularExpression(
            pattern: ключ + #"\s*:?\s*\[?\s*"((?:[^"\\]|\\.)*)""#)
        let диапазон = NSRange(текстФраз.startIndex..., in: текстФраз)
        return регулярка.matches(in: текстФраз, range: диапазон).compactMap {
            Range($0.range(at: 1), in: текстФраз).map { r in String(текстФраз[r]) }
        }
    }

    // MARK: Предмет

    @Test("Разбор узнаёт объявление интента и не считает чужое")
    func разборРазличаетФормы() {
        // Проверка самого разбора — первой. Сканер, переставший находить,
        // молчит так же, как тот, кому нечего сказать.
        let проба = """
            struct ОдинIntent: AppIntent {
            struct ДваIntent: LiveActivityIntent {
            struct НеИнтент: View {
            struct Провайдер: AppShortcutsProvider {
            enum СовсемНеТо: Error {
            """
        let найдено = Self.объявленныеИнтенты(в: ["проба.swift": проба])
        #expect(Set(найдено.keys) == ["ОдинIntent", "ДваIntent"], """
            разбор объявлений нашёл \(найдено.keys.sorted()) вместо \
            [ДваIntent, ОдинIntent]. Всё, что ниже, меряло бы разбор.
            """)

        // Комментарий — не объявление. Без этой строки сторож краснел бы
        // на каждом упоминании имени интента в прозе.
        let вПрозе = Self.безКомментариев("""
            // struct ПризракIntent: AppIntent {
            /* struct ДругойПризракIntent: AppIntent { */
            struct ЖивойIntent: AppIntent {
            """)
        #expect(Set(Self.объявленныеИнтенты(в: ["проза.swift": вПрозе]).keys) == ["ЖивойIntent"])

        // А строковый литерал комментарием не становится.
        #expect(Self.безКомментариев(#"let s = "http://togo.app" // хвост"#)
                    .trimmingCharacters(in: .whitespaces) == #"let s = "http://togo.app""#)
    }

    @Test("У каждого интента есть готовая фраза или записанная причина")
    @MainActor
    func каждыйИнтентУчтён() throws {
        let файлы = try Self.исходники()

        // Контроль ПЕРВЫМ и из другого канала: было ли что проверять.
        #expect(файлы.count >= 150, """
            обход нашёл \(файлы.count) файлов .swift при 250+ в проекте. \
            Читается не то дерево — вывод ниже был бы о сканере.
            """)

        let объявленные = Self.объявленныеИнтенты(в: файлы)
        #expect(объявленные.count >= 7, """
            интентов в дереве \(объявленные.count) при восьми на 24.10.2026: \
            \(объявленные.keys.sorted()). Порог тупой нарочно — он ловит \
            ослепший разбор, а не рост набора.
            """)

        let текстФраз = Self.безКомментариев(
            try String(contentsOf: Self.файлФраз, encoding: .utf8))
        let сФразой = Self.сГотовойФразой(текстФраз)

        // **Контроль разбора ЖИВЫМ КОДОМ, снятый в том же замере.**
        // `appShortcuts` — не проза, его исполняет система. Разъехалось
        // с разбором — виноват разбор, и это видно ДО вывода о проекте.
        #expect(сФразой.count == TogoShortcuts.appShortcuts.count, """
            разбор насчитал \(сФразой.count) записей `intent:` \
            (\(сФразой.sorted())), а живой `TogoShortcuts.appShortcuts` \
            отдаёт \(TogoShortcuts.appShortcuts.count). Расходится РАЗБОР, \
            а не проект: правь регулярку, прежде чем читать строки ниже.
            """)

        let безФразы = TogoShortcuts.безГотовойФразы

        // 1. Ни один интент не остался неучтённым.
        let ничьи = Set(объявленные.keys)
            .subtracting(сФразой)
            .subtracting(безФразы.keys)
            .sorted()
        #expect(ничьи.isEmpty, """
            интент объявлен, но ни готовой фразы, ни записанной причины \
            у него нет: \(ничьи.map { "\($0) (\(объявленные[$0] ?? "?"))" }).

            Это и есть тот пропуск, из-за которого `StartWalkIntent` \
            и `FinishWalkIntent` полгода не звались голосом и никто \
            не мог сказать, решение это или забыли. Лечится одним из двух, \
            и оба — в `TogoShortcuts`: либо `AppShortcut(intent:…)`, \
            либо запись в `безГотовойФразы` с причиной.
            """)

        // 2. Запись, пережившая свой интент, тоже красит: под неё можно
        //    спрятать новый. Тот же храповик, что у долгов локализации.
        let протухшие = Set(безФразы.keys).subtracting(объявленные.keys).sorted()
        #expect(протухшие.isEmpty, """
            `безГотовойФразы` числит интенты, которых в дереве нет: \
            \(протухшие). Удали записи — иначе они разрешают вернуть \
            интент с этим именем без единой фразы и без вопросов.
            """)

        // 3. Противоречие: и фраза есть, и причина её отсутствия.
        let вОбоих = Set(безФразы.keys).intersection(сФразой).sorted()
        #expect(вОбоих.isEmpty, """
            интент одновременно с готовой фразой и в списке «без фразы»: \
            \(вОбоих). Один из двух списков врёт, и читающий не знает, какой.
            """)

        // 4. Причина проверяется длиной. «Служебное» и «не нужно» —
        //    не причина, а отметка о том, что вопрос закрыли, не ответив.
        let пустые = безФразы
            .filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 }
            .keys.sorted()
        #expect(пустые.isEmpty, """
            причина короче сорока знаков у \(пустые) — это отметка, \
            а не довод. Следующий прочтёт её как «так и надо» и не пойдёт \
            проверять.
            """)

        print("""
            ГРАНИЦА: сторож видит `struct X: …Intent`, объявленный \
            в Togo/TogoShared/TogoWidgets, и `intent: X()` в appShortcuts. \
            Он НЕ видит интент, объявленный `final class`, собранный \
            макросом или заведённый в зависимости. Он НЕ проверяет, \
            что Siri действительно подхватила фразу: это внешняя \
            система, из прогона недостижимая. Учтено интентов: \
            \(объявленные.count), с фразой \(сФразой.count), \
            с причиной \(безФразы.count).
            """)
    }

    @Test("Готовые фразы не сталкиваются между собой")
    func фразыНеСталкиваются() throws {
        let текстФраз = Self.безКомментариев(
            try String(contentsOf: Self.файлФраз, encoding: .utf8))

        let фразы = Self.литералы(текстФраз, после: "phrases")
            + Self.литералыПродолжения(текстФраз)
        #expect(фразы.count >= 10, """
            фраз разобрано \(фразы.count) при десяти на 24.10.2026 — \
            по две у каждой из пяти готовых команд. Разбор ослеп.
            """)

        let повторы = Dictionary(grouping: фразы, by: { $0 })
            .filter { $0.value.count > 1 }.keys.sorted()
        #expect(повторы.isEmpty, """
            одна и та же фраза объявлена дважды: \(повторы). Siri берёт \
            одну из двух команд, и какую — не узнать ни из кода, ни \
            с экрана.
            """)

        // Apple требует имя приложения в КАЖДОЙ фразе. Без него команда
        // не регистрируется вовсе — молча, в рантайме.
        let безИмени = фразы.filter { !$0.contains("applicationName") }
        #expect(безИмени.isEmpty, """
            фраза без `\\(.applicationName)`: \(безИмени). Такая команда \
            не регистрируется у Siri вовсе, и узнать это можно только \
            телефоном.
            """)

        let имена = Self.литералы(текстФраз, после: "shortTitle")
        #expect(имена.count >= 5, "коротких имён разобрано \(имена.count) при пяти")
        let повторыИмён = Dictionary(grouping: имена, by: { $0 })
            .filter { $0.value.count > 1 }.keys.sorted()
        #expect(повторыИмён.isEmpty, """
            два разных действия с одним коротким именем: \(повторыИмён). \
            В галерее «Команд» они встанут двумя одинаковыми плитками.
            """)
    }

    /// Вторая и дальше фразы массива: `"…", "…"` после `phrases: [`.
    ///
    /// Разделена с первой нарочно — регулярка «ключ + первый литерал»
    /// не умеет повторяться по массиву, а жадная по всему блоку
    /// захватывала бы `shortTitle` и `systemImageName`.
    static func литералыПродолжения(_ текст: String) -> [String] {
        var собрано: [String] = []
        let регулярка = try! NSRegularExpression(
            pattern: #"phrases:\s*\[([^\]]*)\]"#, options: [.dotMatchesLineSeparators])
        let литерал = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let диапазон = NSRange(текст.startIndex..., in: текст)
        for m in регулярка.matches(in: текст, range: диапазон) {
            guard let тело = Range(m.range(at: 1), in: текст) else { continue }
            let кусок = String(текст[тело])
            let внутри = NSRange(кусок.startIndex..., in: кусок)
            let все = литерал.matches(in: кусок, range: внутри).compactMap {
                Range($0.range(at: 1), in: кусок).map { r in String(кусок[r]) }
            }
            собрано += Array(все.dropFirst())   // первую уже взял `литералы(_:после:)`
        }
        return собрано
    }
}
