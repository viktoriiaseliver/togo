import Testing
import Foundation
@testable import Togo

/// У каждого поля модели записано, про **семью** оно или про **этот
/// телефон**.
///
/// **Чем это оплачено.** 22.09.2026 нашли и починили `isMe`: поле
/// хранится в модели, значит уезжает в общий дневник, и на втором
/// телефоне «я» оказалась карточкой владельца (`5c70324`).
/// Предупреждение об этом записали комментарием в `AppState.swift`.
///
/// 23.09 тот же класс вернулся **в тот же файл**, двадцатью строками
/// ниже комментария, и предложили его **двое независимо**: одна сессия
/// в письме, другая в коде. Комментарий был верный, свежий, стоял на
/// экране выше — и не помог.
///
/// Ни расстояние, ни возраст ни при чём: **инвариант и его нарушение
/// жили вместе**. Поймал только тест, оказавшийся строже формулировки,
/// под которую писался.
///
/// > **Знание в комментарии не защищает соседний код. Защищает только
/// > то, что выполняется.**
///
/// Форма взята у Timer (`Shared/CloudSync.swift` + `CloudSyncTests`):
/// два списка, у каждого ключа причина, и правило «третьего не дано,
/// и это проверяется». Там она написана для ключей настроек, здесь —
/// для полей моделей, потому что именно у них «про телефон» и «про
/// семью» лежат вперемешку и отличаются только чтением.
@Suite("Поле знает, про семью оно или про телефон")
struct DeviceLocalFieldTests {

    /// Поля, которые **не должны** уезжать: они посчитаны от этого
    /// устройства и на другом значат не то же самое.
    private static let проЭтотТелефон: [String: String] = [
        "FamilyMember.isMe": """
            кто «я» — свойство телефона, а не семьи. Уехав, метка \
            сделала своей карточку владельца на втором телефоне \
            (5c70324). Своя карточка помнится в UserDefaults \
            (`family.me`), а это поле читать можно только в своём \
            дневнике — см. FamilyResolver
            """,
        "LogEvent.isSynced": """
            всегда true и в интерфейсе намеренно не показано. Живого \
            нарушения нет; поставит кто-нибудь false — уедет и будет \
            значить не то же самое
            """,
    ]

    /// Поля, которым уезжать положено: это факты про собаку и семью.
    /// Проверяются не по одному — списком, чтобы «не подумали» было
    /// видно.
    private static let проСемью: Set<String> = [
        "FamilyMember.id", "FamilyMember.name", "FamilyMember.roleRaw",
        "FamilyMember.note", "FamilyMember.customPermissionsRaw",
        // Кто на дежурстве — факт про семью, а не про телефон:
        // его должны видеть все, и напоминания идут дежурному.
        "FamilyMember.isOnDuty", "FamilyMember.dutyUntil",
        "FamilyMember.inviteToken", "FamilyMember.inviteExpiresAt",
        "FamilyMember.accessExpiresAt", "FamilyMember.acceptedAt",

        // Лента. Всё здесь — факты о том, что случилось с собакой:
        // на другом телефоне они значат ровно то же самое.
        "LogEvent.id", "LogEvent.date", "LogEvent.kindRaw",
        // Кто записал. Имя, а не «я»: именно поэтому оно и ездит —
        // «кто дал дозу» перестаёт быть вопросом с ответом, если
        // подписывать записи местоимением.
        "LogEvent.authorName", "LogEvent.note",
        // Когда записали, в отличие от `date` — когда случилось.
        // Факт о записи, а не о телефоне: «отметили вечером за утро»
        // одинаково верно у обоих.
        "LogEvent.enteredAt",
        // Чем записали: экран, голос, виджет. Соблазн счесть это
        // «про телефон» есть, и он ошибочный — это свойство записи,
        // и второму человеку оно говорит, насколько ей доверять.
        "LogEvent.originRaw",
        "LogEvent.isDayOnly", "LogEvent.outcomeRaw", "LogEvent.askSignalRaw",
        "LogEvent.durationSeconds", "LogEvent.stoolFormRaw",
        "LogEvent.stoolFlagsRaw", "LogEvent.grams", "LogEvent.milliliters",
        "LogEvent.fromPortion", "LogEvent.reactionTriggerRaw",
        "LogEvent.reactionDistanceRaw", "LogEvent.incidentKindRaw",
        "LogEvent.incidentDetailRaw", "LogEvent.toldFamily",
        "LogEvent.trainingSessionID", "LogEvent.medicationID",
        "LogEvent.careTaskID", "LogEvent.walkEventID",
        "LogEvent.deletedAt", "LogEvent.deletedBy", "LogEvent.changedAt",
        // Кто поправил запись. Та же причина, что у `deletedBy`:
        // это имя человека, а не свойство телефона, и на другом
        // телефоне оно значит ровно то же. В дневнике на семью это
        // и есть главный вопрос к исправленной записи — граммы
        // поправил тот, кто кормил, или тот, кто решил, что было иначе.
        "LogEvent.editedBy",
        "LogEvent.dog",
    ]

    /// Модели, поля которых ещё не разобраны.
    ///
    /// Список **уменьшается и не растёт** — это его смысл. Новая модель
    /// в нём появиться не может: она упрётся в проверку ниже.
    ///
    /// Разобраны сначала те две, где нарушение уже случалось.
    private static let ещёНеРазобраны: Set<String> = [
        "Dog", "DogDocument", "DayOut", "HeatRecord", "FoodStock",
        "CareTask", "Medication", "DoseRecord", "WeightEntry",
        "TrainingStep", "TrainingSession", "ProcedureSkill",
        "Episode", "Trip",
    ]

    /// Хранимые поля каждой `@Model` — из исходника, а не списком.
    ///
    /// Членом класса считается только то, что стоит на уровне тела:
    /// разбор по одной строке не отличает поле от локальной переменной
    /// внутри вычисляемого свойства и ошибается **в сторону полноты**.
    /// Так 23.09 снимок схемы вышел на поле богаче настоящего, и
    /// хранилище не открылось.
    private func поля() throws -> [String: [String]] {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TogoShared/Models")
        var собрано: [String: [String]] = [:]

        let обход = FileManager.default.enumerator(at: корень, includingPropertiesForKeys: nil)
        while let элемент = обход?.nextObject() as? URL {
            guard элемент.pathExtension == "swift",
                  let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }

            let строки = текст.components(separatedBy: .newlines)
            var i = 0
            while i < строки.count {
                guard строки[i].trimmingCharacters(in: .whitespaces) == "@Model",
                      i + 1 < строки.count,
                      let имя = строки[i + 1]
                        .firstMatch(#"(?:nonisolated )?final class (\w+)"#)
                else { i += 1; continue }

                var глубина = 0
                var найденные: [String] = []
                var j = i + 1
                while j < строки.count {
                    let строка = строки[j]
                    // Уровень тела класса — **единица**, а не ноль:
                    // строка `final class X {` уже открыла скобку.
                    // Первая редакция сравнивала с нулём, не находила
                    // ни одного поля и была зелёной при любом новом —
                    // поймала подделка, а не чтение.
                    let член = глубина == 1 && строка.firstMatch(#"^    \S"#) != nil
                    глубина += строка.filter { $0 == "{" }.count
                    глубина -= строка.filter { $0 == "}" }.count
                    if j > i + 1, глубина == 0 { break }
                    guard член else { j += 1; continue }
                    let голая = строка.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"^@\w+\([^)]*\)\s*"#,
                                              with: "", options: .regularExpression)
                    if !голая.contains("{"),
                       let поле = голая.firstMatch(#"^var (\w+): "#) {
                        найденные.append(поле)
                    }
                    j += 1
                }
                собрано[имя] = найденные
                i = j
            }
        }
        return собрано
    }

    @Test("Каждое поле разобранной модели попало ровно в один список")
    func третьегоНеДано() throws {
        let модели = try поля()
        #expect(модели.count >= 14, """
            моделей разобрано \(модели.count) — разбор не состоялся.
            Набор, которому нечего проверять, молчит так же, как набор,
            у которого всё хорошо.
            """)

        // **Счёт полей, а не только моделей.** Первая редакция этой
        // проверки считала модели и молчала: поля разбирались в пустой
        // список, «без решения» получалось ноль, и сторож был зелёным
        // при любом новом поле. Поймала подделка — дописанное
        // `lastSeenOnThisPhone` прошло насквозь.
        //
        // Сканер, переставший что-либо находить, молчит так же, как
        // тот, кому нечего сказать.
        #expect(модели["FamilyMember"]?.count ?? 0 >= 10, """
            у FamilyMember разобрано \(модели["FamilyMember"]?.count ?? 0) полей —
            разбор полей не состоялся, и сторож зелен впустую.
            """)
        #expect(модели["LogEvent"]?.count ?? 0 >= 10, """
            у LogEvent разобрано \(модели["LogEvent"]?.count ?? 0) полей.
            """)

        var безРешения: [String] = []
        var вДвух: [String] = []
        for (модель, поля) in модели.sorted(by: { $0.key < $1.key })
        where !Self.ещёНеРазобраны.contains(модель) {
            for поле in поля {
                let ключ = "\(модель).\(поле)"
                let телефон = Self.проЭтотТелефон[ключ] != nil
                let семья = Self.проСемью.contains(ключ)
                if телефон && семья { вДвух.append(ключ) }
                if !телефон && !семья { безРешения.append(ключ) }
            }
        }

        #expect(вДвух.isEmpty, "поле и ездит, и не ездит: \(вДвух)")
        #expect(безРешения.isEmpty, """
            у поля не записано, про семью оно или про этот телефон:
            \(безРешения)

            Ответь на один вопрос: значит ли это поле на ДРУГОМ телефоне
            то же самое? Если нет — оно про устройство, и уезжать ему
            нельзя. Так `isMe` сделал своей карточку владельца.
            """)
    }

    @Test("Список неразобранных только уменьшается")
    func долгНеРастёт() throws {
        let модели = Set(try поля().keys)
        let лишние = Self.ещёНеРазобраны.subtracting(модели).sorted()
        #expect(лишние.isEmpty, """
            в списке неразобранных числятся модели, которых нет:
            \(лишние). Убери их — список, переживший свои строки,
            разрешает вернуть то, что уже разобрано.
            """)

        let новые = модели.subtracting(Self.ещёНеРазобраны)
            .subtracting(["FamilyMember", "LogEvent"])
            .sorted()
        #expect(новые.isEmpty, """
            появилась модель, которую никто не разбирал: \(новые).
            Впиши её поля в один из двух списков — или в список
            неразобранных, но тогда назови это вслух.
            """)
    }

    @Test("У каждого «не ездит» записана причина")
    func причиныЕсть() {
        let безПричины = Self.проЭтотТелефон
            .filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.key).sorted()
        #expect(безПричины.isEmpty, """
            «не ездит» без причины: \(безПричины).
            Исключение без причины через месяц неотличимо от дыры.
            """)
    }
}

private extension String {
    /// Первая группа первого совпадения — или `nil`.
    func firstMatch(_ образец: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: образец),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }
        let группа = m.numberOfRanges > 1 ? 1 : 0
        return Range(m.range(at: группа), in: self).map { String(self[$0]) }
    }
}
