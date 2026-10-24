import Testing
import Foundation

/// «Удалить все данные» стирает и отметки о данных, а не только данные.
///
/// **Решение Виктории 24.10.2026: «как при первой установке».**
///
/// До него `deleteEverything()` стирал шестнадцать моделей и не трогал
/// в `UserDefaults` ничего. Заготовки навыков уезжали вместе
/// с `ProcedureSkill`, а галочка «заготовки уже созданы» оставалась
/// `true` — и человек после полного удаления оставался **без навыков
/// и без того, что их когда-то заводили**.
///
/// > **Данные и отметка о данных жили в разных хранилищах, и стирало
/// > их разное.** Флаг переживал удаление не по решению, а по
/// > устройству: `@AppStorage` просто не входит в `ModelContext`.
///
/// # Зачем сторож, если ключ сейчас один
///
/// Потому что он **один сейчас**. Второй `@AppStorage` заведут, не зная
/// про этот список, и список разойдётся с действительностью молча —
/// ровно так, как у нас уже расходились две копии порога сюит и два
/// списка полей обмена.
///
/// Сторож не решает за автора, что делать с новым ключом: язык
/// и согласия при удалении данных стирать НЕ надо. Он требует одного —
/// **чтобы решение было принято**, а не пропущено.
@Suite("«Удалить все данные» чистит и отметки в UserDefaults")
struct УдалитьВсёЧиститОтметкиTests {

    /// Ключи `@AppStorage`, живущие в продукте на 24.10.2026.
    ///
    /// Один. Замер: `grep -rn --no-ignore-files "@AppStorage"` по трём
    /// каталогам продукта, с вычетом комментариев, — одно объявление.
    static let известныеКлючи: Set<String> = ["procedureSkills.seeded"]

    /// Ключи, которые «Удалить все данные» обязано стереть.
    ///
    /// Сейчас совпадает с полным списком. Разойдётся — когда появится
    /// ключ, который удалять **не** надо: язык, согласия, настройки
    /// уведомлений. Тогда строка ниже станет меньше, и разница будет
    /// названа здесь.
    static let стираемыеПриУдалении: Set<String> = ["procedureSkills.seeded"]

    private static var корень: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func безКомментариев(_ текст: String) -> String {
        var вне = ""
        var вБлоке = false
        for строка in текст.components(separatedBy: .newlines) {
            var s = Substring(строка)
            if вБлоке {
                guard let конец = s.range(of: "*/") else { continue }
                s = s[конец.upperBound...]
                вБлоке = false
            }
            if let начало = s.range(of: "/*") {
                if let конец = s.range(of: "*/", range: начало.upperBound..<s.endIndex) {
                    s = s[s.startIndex..<начало.lowerBound] + s[конец.upperBound...]
                } else {
                    s = s[s.startIndex..<начало.lowerBound]
                    вБлоке = true
                }
            }
            if let черта = s.range(of: "//") {
                s = s[s.startIndex..<черта.lowerBound]
            }
            вне += s + "\n"
        }
        return вне
    }

    /// Все ключи `@AppStorage` в коде продукта — **без комментариев**.
    ///
    /// Вырезка обязательна: в `DataPrivacyScreen` слово `@AppStorage`
    /// набрано в объяснении, и сторож без неё посчитал бы прозу.
    private func ключиВКоде() -> (ключи: Set<String>, файлов: Int) {
        let fm = FileManager.default
        var ключи: Set<String> = []
        var файлов = 0
        for каталог in ["Togo", "TogoShared", "TogoWidgets"] {
            guard let обходчик = fm.enumerator(
                at: Self.корень.appendingPathComponent(каталог),
                includingPropertiesForKeys: nil) else { continue }
            for случай in обходчик {
                guard let url = случай as? URL, url.pathExtension == "swift",
                      let текст = try? String(contentsOf: url, encoding: .utf8) else { continue }
                файлов += 1
                let код = безКомментариев(текст)
                var остаток = Substring(код)
                while let метка = остаток.range(of: "@AppStorage(\"") {
                    остаток = остаток[метка.upperBound...]
                    guard let кавычка = остаток.firstIndex(of: "\"") else { break }
                    ключи.insert(String(остаток[остаток.startIndex..<кавычка]))
                    остаток = остаток[кавычка...]
                }
            }
        }
        return (ключи, файлов)
    }

    @Test("Обход просмотрел файлы: отметки в UserDefaults")
    func былоЧтоПроверять() {
        let (_, файлов) = ключиВКоде()
        #expect(файлов >= 180, """
            Обход увидел \(файлов) файлов при ожидаемых 180+. Это отказ
            сканера: пустой обход даёт пустое множество ключей, а пустое
            множество — зелёный на обеих проверках ниже.
            """)
    }

    @Test("Новый ключ @AppStorage требует решения об удалении данных")
    func каждыйКлючРазобран() {
        let (ключи, _) = ключиВКоде()
        let незнакомые = ключи.subtracting(Self.известныеКлючи).sorted()
        #expect(незнакомые.isEmpty, """
            В продукте появились ключи @AppStorage, которых нет в разборе:
            \(незнакомые.joined(separator: ", "))

            Про каждый надо решить, стирает ли их «Удалить все данные».
            Решение Виктории 24.10.2026 — «как при первой установке»:
            отметка о данных уходит вместе с данными. Но язык, согласия
            и настройки уведомлений человек удалить НЕ просил.

            Решив, впиши ключ в `известныеКлючи`, а если он стирается —
            ещё и в `стираемыеПриУдалении` И в сам `deleteEverything()`.
            """)
    }

    @Test("Каждый стираемый ключ назван в deleteEverything")
    func стираемыеНазваныВКоде() throws {
        let файл = Self.корень
            .appendingPathComponent("Togo/Features/Settings/DataPrivacyScreen.swift")
        let текст = try String(contentsOf: файл, encoding: .utf8)
        let код = безКомментариев(текст)

        // Контроль инструмента: имя самой функции в коде есть.
        // Без него «ключ не найден» неотличимо от «файл не прочитан».
        #expect(код.contains("func deleteEverything"),
                "в \(файл.lastPathComponent) нет deleteEverything — разбор не состоялся")

        for ключ in Self.стираемыеПриУдалении.sorted() {
            #expect(код.contains("\"\(ключ)\""), """
                Ключ «\(ключ)» числится стираемым, но в коде
                `deleteEverything()` его нет. После «Удалить все данные»
                он переживёт удаление, и человек останется без данных,
                но с отметкой, что они были.
                """)
        }
    }
}
