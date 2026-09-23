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

    /// Мама получила «со-владельца», а на её телефоне половины
    /// функционала не оказалось. Причина не в роли: `isMe` хранится
    /// в модели и уезжает в общий дневник, поэтому на втором телефоне
    /// «я» — это карточка владельца. Плюс `adopt` звали только при
    /// ручной правке карточки, так что до неё действовал владелец
    /// по умолчанию.
    @Test("На втором телефоне я — не тот, у кого стоит isMe")
    func secondPhoneDoesNotTrustIsMe() {
        let хозяйка = FamilyMember(name: "Виктория", role: .owner, isMe: true)
        let мама = FamilyMember(name: "Мама", role: .coOwner)

        let state = AppState()
        state.myMemberID = мама.id
        state.adoptMe(from: [хозяйка, мама])

        #expect(state.role == .coOwner, "взяли свою карточку, а не чужую с isMe")
        #expect(state.currentUserName == "Мама")
        #expect(!state.can(.editTreatment), "схему лечения меняет владелец")
        #expect(state.can(.giveDose))
        #expect(state.can(.manageFamily))
    }

    @Test("Себя не опознали — чужую роль не берём")
    func unknownMemberKeepsRole() {
        let хозяйка = FamilyMember(name: "Виктория", role: .owner, isMe: true)
        let мама = FamilyMember(name: "Мама", role: .coOwner)

        // **Без ручной подстановки роли, и это главное в этом тесте.**
        //
        // Прежняя редакция начиналась со `state.role = .helper` —
        // состояния, которого у живого `AppState()` не бывает никогда.
        // Тест был зелёным, потому что обошёл настоящее начальное
        // условие: роль по умолчанию была `.owner`, то есть все права.
        //
        // Он и комментарий к `adoptMe` были написаны вместе с починкой
        // и выражали одно и то же понимание — поэтому и не поймали друг
        // друга. Дважды переписанная от руки цифра не проверяется сама
        // собой.
        let гостьНаЧужомТелефоне = AppState()
        гостьНаЧужомТелефоне.adoptMe(from: [хозяйка, мама], гость: true)

        // Проверяем права, а не равенство роли: на экранах спрашивают
        // про право, и именно оно стреляет.
        #expect(!гостьНаЧужомТелефоне.can(.editTreatment),
                "неопознанный гость получил право менять схему лечения")
        #expect(!гостьНаЧужомТелефоне.can(.manageFamily),
                "неопознанный гость получил право раздавать права")
        #expect(!гостьНаЧужомТелефоне.can(.logBasics),
                "неопознанный гость пишет в чужой дневник")
        #expect(гостьНаЧужомТелефоне.can(.seeMedical), "читать наблюдателю можно")
    }

    /// Вторая половина того же решения: в СВОЁМ дневнике неопознанность
    /// значит другое.
    ///
    /// Участники — карточки, которые завёл сам хозяин, и себя среди них
    /// он мог не заводить. Отнять права значило бы запереть человека
    /// в собственном дневнике: он не смог бы записать даже выход.
    @Test("В своём дневнике неопознанный остаётся владельцем")
    func unknownMemberInOwnDiaryKeepsOwner() {
        let мама = FamilyMember(name: "Мама", role: .coOwner)
        let ситтер = FamilyMember(name: "Ситтер", role: .helper)

        let свойТелефон = AppState()
        свойТелефон.adoptMe(from: [мама, ситтер], гость: false)

        #expect(свойТелефон.can(.logBasics), "хозяин не может записать выход в своём дневнике")
        #expect(свойТелефон.can(.editTreatment))
    }

    /// Начальное значение проверяется отдельно: именно оно было
    /// дефектом, и именно его легче всего вернуть обратно.
    @Test("Свежий AppState не раздаёт прав")
    func freshStateGrantsNothingDangerous() {
        let свежий = AppState()
        #expect(!свежий.can(.editTreatment), """
            роль по умолчанию снова открывает всё. Отказ обязан
            закрывать: `adoptMe` расширяет права, а не подтверждает
            выданные заранее.
            """)
        #expect(!свежий.can(.manageFamily))
    }

    @Test("Один участник — это я, даже без запомненной карточки")
    func singleMemberIsMe() {
        let одна = FamilyMember(name: "Виктория", role: .owner, isMe: true)
        let state = AppState()
        state.adoptMe(from: [одна])
        #expect(state.role == .owner)
        #expect(state.myMemberID == одна.id, "запомнили на будущее")
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
