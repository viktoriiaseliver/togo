import Testing
import Foundation
@testable import Togo

/// Откат хранилища не молчит ни на одной ступени.
///
/// Лестница такая: iCloud → локально → в памяти. Каждая ступень ниже
/// значит меньше обещаний, и о каждой человек обязан узнать не постфактум.
///
/// - **В памяти** говорит давно: плашка на главном экране, живёт, пока
///   положение не исправлено. Это проверяет `EphemeralBannerTests` —
///   здесь только сверка, что она осталась.
/// - **Файл есть, но не открылся** — экран «Дневник не открылся»
///   вместо пустого онбординга. Проверяет `SchemaMigrationTests`.
/// - **iCloud → локально** до 23.09.2026 отвечал одним текстом
///   на три разные причины, и совет в нём — «включи iCloud Drive» —
///   двум из трёх не помогал ничем.
@Suite("Откат хранилища называет причину")
struct CloudFallbackTests {

    /// Главное: у каждой причины свой текст, и ни один не советует
    /// чинить не то.
    @Test("Три причины «не iCloud» отвечают по-разному")
    func причиныРазличимы() {
        let причины: [Persistence.CloudState] =
            [.noAccount, .restricted, .unavailable, .noEntitlement, .openFailed]
        let заголовки = Set(причины.map(\.title))
        let тексты = Set(причины.map(\.detail))

        #expect(заголовки.count == причины.count, """
            две причины отвечают одним заголовком. Человек, у которого
            сборка без права на iCloud, и человек с выключенным iCloud
            Drive чинят разное.
            """)
        #expect(тексты.count == причины.count, "две причины отвечают одним текстом")
    }

    /// Совет «включи iCloud Drive» уместен ровно там, где он помогает.
    @Test("Сборке без права не советуют лезть в настройки телефона")
    func советНеВводитВЗаблуждение() {
        let текст = Persistence.CloudState.noEntitlement.detail
        #expect(!текст.contains("настройках телефона"))
        #expect(!текст.contains("Включи iCloud Drive"), """
            права нет у самой сборки: настройка у человека уже включена,
            и он потратит время на то, что не поможет.
            """)
        #expect(текст.contains("сборки"), "причина не названа")
    }

    /// Ступень, которая до сих пор молчала целиком.
    @Test("«Право есть, а библиотека не открылась» говорит прямо")
    func открытиеНеУдалосьНазвано() {
        let текст = Persistence.CloudState.openFailed.detail
        #expect(текст.contains("только на этом телефоне"), """
            человек считает, что записи уезжают в iCloud, и узнаёт
            обратное, потеряв телефон.
            """)
    }

    /// Хорошим считается ровно одно состояние. Иначе плашка «всё в порядке»
    /// повиснет над дневником, который никуда не уезжает.
    @Test("Хорошее состояние одно")
    func хорошееОдно() {
        let все: [Persistence.CloudState] =
            [.syncing, .noAccount, .restricted, .unavailable, .noEntitlement, .openFailed]
        #expect(все.filter(\.isGood).count == 1)
        #expect(Persistence.CloudState.syncing.isGood)
    }

    /// Плашка про хранилище в памяти — на месте и привязана к флагу,
    /// а не к догадке экрана.
    @Test("Плашка «записи не сохраняются» осталась на главном экране")
    func плашкаВПамятиЖива() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let экран = try String(
            contentsOf: корень.appendingPathComponent("Togo/Features/Today/TodayScreen.swift"),
            encoding: .utf8)
        #expect(экран.contains("Persistence.isEphemeral"), """
            хранилище в памяти — молчаливый отказ на уровне всего дневника:
            человек отмечает дозу, получает подтверждение, и запись
            не сохраняется никуда.
            """)
        #expect(экран.contains("Записи сейчас не сохраняются"))
    }
}
