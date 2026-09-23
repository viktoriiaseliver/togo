import Testing
import Foundation
@testable import Togo

/// Созданное приглашение обязано пережить уход с экрана.
///
/// Замер 23.09.2026: сорок четыре захода на «Семью» за девять сессий
/// и ни одной отправки. Причина не в экране — Виктория объяснила, что
/// там пытались настроить общий доступ, — а в том, что созданный
/// `CKShare` лежал только в `@State`. Человек создавал ссылку, уходил,
/// возвращался и снова видел «Создать приглашение»: отправить её можно
/// было только не уходя, вторым тапом подряд. Каждый заход был первым.
///
/// Проверяется исходником, а не поведением: `CKShare` без живого iCloud
/// не собрать, а забыть `.task` при следующей правке экрана — легко.
/// Тест сторожит ровно то, что сломалось.
@Suite("Приглашение переживает уход с экрана")
@MainActor
struct InviteSurvivesScreenTests {

    private func текст(_ путь: String) throws -> String {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: корень.appendingPathComponent(путь), encoding: .utf8)
    }

    @Test("Оба экрана ищут уже созданное приглашение при появлении")
    func экраныСпрашиваютОблако() throws {
        for путь in ["Togo/Features/Family/FamilyScreen.swift",
                     "Togo/Features/Family/SharedDiaryScreen.swift"] {
            #expect(try текст(путь).contains("FamilyShare.existing()"), """
                \(путь) не спрашивает облако об уже созданном приглашении.
                Человек создаст ссылку, уйдёт с экрана и вернётся к кнопке
                «Создать приглашение» — отправить созданное станет нечем.
                """)
        }
    }

    @Test("Путь приглашения размечен в обе стороны")
    func путьРазмечен() throws {
        for путь in ["Togo/Features/Family/FamilyScreen.swift",
                     "Togo/Features/Family/SharedDiaryScreen.swift"] {
            let исходник = try текст(путь)
            #expect(исходник.contains("\"invite\""),
                    "\(путь): удача приглашения не попадает в журнал")
            #expect(исходник.contains("FamilyShare.причина(error)"),
                    "\(путь): отказ попадёт в журнал без вида — лечить будет нечем")
        }
    }

    /// Красная линия журнала: вид отказа — да, текст системы — нет.
    /// В `localizedDescription` у CloudKit бывают имя контейнера и адрес
    /// почты участника, а журнал действий человек отдаёт нам сам.
    @Test("В журнал уходит вид отказа, а не его текст")
    func безЛичногоВЖурнале() throws {
        for путь in ["Togo/Features/Family/FamilyScreen.swift",
                     "Togo/Features/Family/SharedDiaryScreen.swift"] {
            let исходник = try текст(путь)
            #expect(!исходник.contains("UsageLog.note(.record, \"invite:\\(error"),
                    "\(путь): в журнал уходит текст ошибки целиком")
            #expect(!исходник.contains("localizedDescription)\", on: ."),
                    "\(путь): в журнал уходит localizedDescription")
        }
    }

    @Test("Вид отказа называется словом, а не пустотой")
    func причиныНазваны() {
        #expect(FamilyShare.причина(FamilyShare.ShareError.noAccount) == "noAccount")
        #expect(FamilyShare.причина(FamilyShare.ShareError.noEntitlement) == "noEntitlement")
        #expect(FamilyShare.причина(FamilyShare.ShareError.notOwner) == "notOwner")
        #expect(FamilyShare.причина(URLError(.notConnectedToInternet)) == "unknown")
    }

    /// «Общий дневник» — отдельный экран, и время на нём числилось
    /// за «Семьёй». Список экранов закрытый: без своего случая журнал
    /// не отличает попытку настроить обмен от чтения списка людей.
    @Test("Общий дневник есть в списке экранов журнала")
    func экранЗаведён() {
        #expect(UsageLog.Screen(rawValue: "sharedDiary") != nil)
        #expect(UsageLog.Screen.sharedDiary.title == "Общий дневник")
    }
}
