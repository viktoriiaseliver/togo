import Testing
import Foundation
@testable import Togo

/// Кто видит медицинское.
///
/// До 23.09 вкладка «Здоровье» открывалась одним условием —
/// `dog?.isOnTreatment == true`, — и права там не было вовсе. Ситтер
/// с ролью «помощник» увидел бы препараты, часы, окно натощак, дозы
/// и отчёт врачу. Сегодня это скрыто не правом, а тем, что собака
/// не уезжает в общий дневник; спринт «все видят всё» эту случайность
/// снимет.
///
/// Решение по всем пяти ролям и обоснование — `docs/матрица-ролей.md`.
/// Здесь оно закреплено: правило живёт в тесте, а не в памяти.
@Suite("Доступ к медицинскому")
@MainActor
struct MedicalAccessTests {

    private func состояние(_ роль: FamilyRole) -> AppState {
        let состояние = AppState.наСвоёмТелефоне()
        состояние.role = роль
        return состояние
    }

    @Test("Помощник медицинского не видит")
    func помощникНеВидит() {
        #expect(!состояние(.helper).can(.seeMedical))
    }

    @Test("Владелец, со-владелец, ухаживающий и наблюдатель — видят")
    func остальныеВидят() {
        for роль in [FamilyRole.owner, .coOwner, .caregiver, .observer] {
            #expect(состояние(роль).can(.seeMedical), "\(роль.title) должен видеть медицинское")
        }
    }

    @Test("Схему лечения по умолчанию меняет только владелец")
    func схемуМеняетВладелец() {
        #expect(состояние(.owner).can(.editTreatment))
        for роль in [FamilyRole.coOwner, .caregiver, .helper, .observer] {
            #expect(!состояние(роль).can(.editTreatment),
                    "\(роль.title) не должен менять схему лечения по умолчанию")
        }
    }

    @Test("Наблюдатель читает медицинское и не пишет ничего")
    func наблюдательТолькоЧитает() {
        let врач = состояние(.observer)
        #expect(врач.can(.seeMedical))
        #expect(!врач.can(.logBasics))
        #expect(!врач.can(.giveDose))
    }

    /// Сторож на само место, а не только на набор прав: условие показа
    /// вкладки должно спрашивать право. Сломать его правкой `RootView`
    /// легко, и по набору прав этого не видно.
    @Test("Вкладка «Здоровье» закрыта правом, а не только лечением")
    func вкладкаСпрашиваетПраво() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Togo/App/RootView.swift")
        let текст = try String(contentsOf: url, encoding: .utf8)
        let строка = текст.components(separatedBy: .newlines)
            .first { $0.contains("isOnTreatment == true") }
        let условие = try #require(строка, "в RootView больше нет условия показа «Здоровья» — проверь, чем оно заменено")
        #expect(условие.contains("can(.seeMedical)"), """
            вкладка «Здоровье» открывается без права: \(условие.trimmingCharacters(in: .whitespaces)).
            Так помощник увидит препараты, дозы и отчёт врачу. Разбор —
            docs/матрица-ролей.md.
            """)
    }
}
