import Testing
import Foundation
import SwiftData
@testable import Togo

/// Вторая собака без подписки.
///
/// До 30.09 после окончания Pro вторая собака работала целиком: ни
/// переключатель, ни `activeDog` на подписку не смотрели, а экран отмены
/// обещал обратное.
@Suite("Вторая собака · замок")
@MainActor
struct DogLockTests {

    private func dogs() throws -> (ModelContext, Dog, Dog) {
        let container = try ModelContainer(
            for: Dog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let стич = Dog(name: "Стич", weightKg: 4.7)
        стич.createdAt = Date(timeIntervalSince1970: 1_000)
        let багира = Dog(name: "Багира", weightKg: 12)
        багира.createdAt = Date(timeIntervalSince1970: 2_000)
        context.insert(стич)
        context.insert(багира)
        try context.save()
        return (context, стич, багира)
    }

    @Test("Основная — заведённая первой, в каком бы порядке ни пришёл список")
    func primaryIsOldest() throws {
        let (_, стич, багира) = try dogs()
        #expect(AppState.основная(из: [багира, стич])?.id == стич.id)
        #expect(AppState.основная(из: [стич, багира])?.id == стич.id)
    }

    @Test("Без Pro выбранная вторая не открывается — открыта основная")
    func lockedWithoutPro() throws {
        let (_, стич, багира) = try dogs()
        let state = AppState.наСвоёмТелефоне()
        state.proАктивен = false
        state.select(багира)
        #expect(state.закрыта(багира, среди: [багира, стич], гость: false))
        #expect(!state.закрыта(стич, среди: [багира, стич], гость: false))
        // `activeDog` спрашивает гостевой режим у телефона; в тестах
        // его ставят ненадолго соседние наборы — тогда замка нет по праву.
        if !SharedZoneOwner.isGuest {
            #expect(state.activeDog(from: [багира, стич])?.id == стич.id)
        }
    }

    @Test("Вернулся Pro — вернулась и выбранная собака, выбор не стёрт")
    func proBringsBack() throws {
        let (_, стич, багира) = try dogs()
        let state = AppState.наСвоёмТелефоне()
        state.select(багира)
        state.proАктивен = true
        #expect(state.activeDog(from: [стич, багира])?.id == багира.id)
        #expect(state.activeDogID == багира.id)
    }

    @Test("Гость в чужом дневнике не закрывается")
    func guestNeverLocked() throws {
        let (_, стич, багира) = try dogs()
        let state = AppState.наСвоёмТелефоне()
        state.proАктивен = false
        #expect(!state.закрыта(багира, среди: [стич, багира], гость: true))
    }
}

/// «Ухаживающий · правка 24 ч» — срок, которого до 30.09 не было в коде.
@Suite("Правка записей · срок роли")
@MainActor
struct EditWindowTests {
    private let сейчас = Date(timeIntervalSince1970: 10_000_000)

    @Test("Ухаживающий правит запись моложе суток и не правит старше")
    func caregiverWindow() {
        let права = FamilyRole.caregiver.defaultPermissions
        #expect(FamilyRole.caregiver.mayEdit(recordedAt: сейчас.addingTimeInterval(-23 * 3600),
                                             with: права, at: сейчас))
        #expect(!FamilyRole.caregiver.mayEdit(recordedAt: сейчас.addingTimeInterval(-25 * 3600),
                                              with: права, at: сейчас))
    }

    @Test("Со-владелец правит без срока, помощник не правит вовсе")
    func otherRoles() {
        let неделя = сейчас.addingTimeInterval(-7 * 24 * 3600)
        #expect(FamilyRole.coOwner.mayEdit(recordedAt: неделя,
                                           with: FamilyRole.coOwner.defaultPermissions, at: сейчас))
        #expect(!FamilyRole.helper.mayEdit(recordedAt: сейчас,
                                           with: FamilyRole.helper.defaultPermissions, at: сейчас))
    }

    @Test("Возраст записи — от момента, когда записали, а не когда было")
    func countsFromEnteredAt() {
        let state = AppState()
        state.role = .caregiver
        let запись = LogEvent(kind: .meal, date: сейчас.addingTimeInterval(-3 * 24 * 3600),
                              authorName: "Мама")
        #expect(!state.canEdit(запись, at: сейчас))
        // Внесена по памяти час назад — свежая запись о давнем.
        запись.enteredAt = сейчас.addingTimeInterval(-3600)
        #expect(state.canEdit(запись, at: сейчас))
    }
}

/// Предпросмотр роли собирает «не увидит / не сможет» из прав.
@Suite("Вид ситтера · из прав")
struct SitterLimitsTests {
    @Test("У помощника в списке медицина и дозы, у владельца — пусто")
    func missingFollowsPermissions() {
        let помощник = Permission.missing(from: FamilyRole.helper.defaultPermissions)
        #expect(помощник.contains(.seeMedical))
        #expect(помощник.contains(.giveDose))
        #expect(!помощник.contains(.logBasics))
        #expect(Permission.missing(from: FamilyRole.owner.defaultPermissions).isEmpty)
        #expect(Permission.allCases.allSatisfy { !$0.withoutIt.isEmpty })
    }
}

/// Протокол контроля: строка «доза → забор» и напоминание за 30 минут.
@Suite("Протокол контроля")
@MainActor
struct ControlProtocolTests {
    private let доза = Date(timeIntervalSince1970: 50_000_000)

    @Test("Заметка о заборе несёт интервал от дозы")
    func drawNoteHasInterval() {
        let забор = доза.addingTimeInterval(4 * 3600 + 12 * 60)
        let заметка = Exporter.drawNote(givenAt: доза, drawnAt: забор)
        #expect(заметка.hasPrefix(Exporter.drawHead))
        #expect(заметка.contains(Fmt.duration(4 * 3600 + 12 * 60)))
        // Без дозы интервала нет — посчитанный от ничего хуже пустого.
        #expect(Exporter.drawNote(givenAt: nil, drawnAt: забор) == Exporter.drawHead)
    }

    @Test("Строка «доза → забор» доезжает до CSV")
    func drawLineReachesCSV() {
        let забор = доза.addingTimeInterval(4 * 3600)
        let запись = LogEvent(kind: .note, date: забор, authorName: "Я")
        запись.note = Exporter.drawNote(givenAt: доза, drawnAt: забор)
        #expect(Exporter.isDraw(запись))
        #expect(Exporter.csv(events: [запись]).contains(Exporter.doseToDraw(givenAt: доза, drawnAt: забор)))
    }

    @Test("Напоминания — за 30 минут до точек, только впереди и без отмеченных")
    func reminderPlan() {
        let обе = ProtocolReminder.plan(givenAt: доза, now: доза.addingTimeInterval(3600))
        #expect(обе.map { $0.hours } == [4, 6])
        #expect(обе.first?.fireAt == доза.addingTimeInterval(4 * 3600 - 30 * 60))

        let однаПрошла = ProtocolReminder.plan(givenAt: доза, now: доза.addingTimeInterval(4 * 3600))
        #expect(однаПрошла.map { $0.hours } == [6])

        let отмечена = ProtocolReminder.plan(givenAt: доза, now: доза, skipping: [4])
        #expect(отмечена.map { $0.hours } == [6])
    }

    @Test("Забор закрывает ближайшую к себе точку")
    func drawCoversNearestPoint() {
        #expect(ProtocolReminder.point(covering: доза.addingTimeInterval(3 * 3600 + 50 * 60), givenAt: доза) == 4)
        #expect(ProtocolReminder.point(covering: доза.addingTimeInterval(5 * 3600 + 30 * 60), givenAt: доза) == 6)
    }
}
