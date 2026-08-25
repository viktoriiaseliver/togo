import Testing
import Foundation
@testable import Togo

@Suite("Права доступа")
@MainActor
struct PermissionTests {
    @Test("Роль — это пресет прав")
    func rolePresets() {
        #expect(FamilyRole.owner.defaultPermissions == Set(Permission.allCases))
        #expect(FamilyRole.helper.defaultPermissions == [.logBasics])
        #expect(!FamilyRole.helper.defaultPermissions.contains(.seeMedical))
        #expect(!FamilyRole.observer.defaultPermissions.contains(.logBasics))
        #expect(FamilyRole.observer.defaultPermissions.contains(.seeMedical))
    }

    @Test("Пока права не трогали, они берутся из роли")
    func inheritsFromRole() {
        let мама = FamilyMember(name: "Мама", role: .caregiver)
        #expect(!мама.hasCustomPermissions)
        #expect(мама.permissions == FamilyRole.caregiver.defaultPermissions)
        #expect(мама.can(.giveDose))
        #expect(!мама.can(.editTreatment))
    }

    @Test("Владелец может выдать право поверх роли")
    func grantBeyondRole() {
        let мама = FamilyMember(name: "Мама", role: .caregiver)
        var права = мама.permissions
        права.insert(.editTreatment)
        мама.permissions = права

        #expect(мама.hasCustomPermissions)
        #expect(мама.can(.editTreatment))
        // Остальное на месте: выдача права не сбрасывает пресет.
        #expect(мама.can(.logBasics))
        #expect(мама.can(.giveDose))
    }

    @Test("Право можно и снять")
    func revoke() {
        let тео = FamilyMember(name: "Тео", role: .coOwner)
        var права = тео.permissions
        права.remove(.exportData)
        тео.permissions = права

        #expect(!тео.can(.exportData))
        #expect(тео.can(.seeMedical))
    }

    @Test("Возврат к роли стирает поимённые права")
    func resetToRole() {
        let лея = FamilyMember(name: "Лея", role: .helper)
        лея.permissions = [.logBasics, .seeMedical]
        #expect(лея.hasCustomPermissions)

        лея.resetPermissions()
        #expect(!лея.hasCustomPermissions)
        #expect(лея.permissions == FamilyRole.helper.defaultPermissions)
    }

    @Test("Набор, совпавший с ролью, перестаёт считаться изменённым")
    func sameAsRoleIsNotCustom() {
        let лея = FamilyMember(name: "Лея", role: .helper)
        лея.permissions = FamilyRole.helper.defaultPermissions
        #expect(!лея.hasCustomPermissions)
    }

    @Test("У владельца нельзя отобрать управление семьёй")
    func ownerKeepsFamilyControl() {
        let виктория = FamilyMember(name: "Виктория", role: .owner, isMe: true)
        var права = виктория.permissions
        права.remove(.manageFamily)
        виктория.permissions = права

        #expect(виктория.can(.manageFamily), "иначе права станет некому раздавать")
    }

    @Test("Смена роли сбрасывает поимённые права в состоянии приложения")
    func appStateResetsOnRoleChange() {
        let state = AppState()
        state.customPermissions = [.logBasics]
        state.role = .caregiver
        #expect(state.customPermissions == nil)
        #expect(state.permissions == FamilyRole.caregiver.defaultPermissions)
    }

    @Test("Состояние приложения подхватывает права участника")
    func appStateAdoptsMember() {
        let ситтер = FamilyMember(name: "Ситтер", role: .helper)
        ситтер.permissions = [.logBasics, .seeMedical, .giveDose]

        let state = AppState()
        state.adopt(ситтер)

        #expect(state.role == .helper)
        #expect(state.can(.seeMedical), "ситтеру на неделю выдали медицинскую часть")
        #expect(state.can(.giveDose))
        #expect(!state.can(.editTreatment))
    }

    @Test("Ситтер с полным доступом — то, ради чего права и настраиваются")
    func sitterWithFullAccess() {
        let ситтер = FamilyMember(name: "Ситтер", role: .helper)
        ситтер.permissions = Set(Permission.allCases).subtracting([.manageFamily])

        #expect(ситтер.can(.editProfile))
        #expect(ситтер.can(.editTreatment))
        #expect(!ситтер.can(.manageFamily), "приглашать он всё же не должен")
    }
}
