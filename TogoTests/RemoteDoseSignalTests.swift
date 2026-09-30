import Testing
import Foundation
import SwiftData
@testable import Togo

/// Чужая отметка дозы обязана дойти до напоминаний.
///
/// `ReminderScheduler` живёт в цели приложения, а приём чужого —
/// в `TogoShared`, который собирается и в виджеты. Мост между ними —
/// сигнал `.togoRemoteDoseChanged`. Без него мама отмечала приём,
/// а у второго человека через полчаса звенело «Доза не отмечена».
@Suite("Чужая отметка дозы → сигнал напоминаниям")
@MainActor
struct RemoteDoseSignalTests {

    /// Что пришло с сигналом. Класс, потому что обработчик сигнала —
    /// `@Sendable`-замыкание; пишется он синхронно на том же потоке,
    /// что и `post`.
    private final class Пойманное: @unchecked Sendable {
        var закрыта: [UUID: Bool] = [:]
    }

    private func отметка(_ id: UUID, дана: Date?, изменено: Date) -> DosePayload {
        DosePayload(
            id: id, medicationID: nil, medicationName: nil,
            scheduledAt: Date(), givenAt: дана, givenBy: дана == nil ? nil : "Мама",
            skippedAt: nil, skippedBy: nil, claimedBy: nil, claimedAt: nil,
            cancelledAt: nil, cancelReason: nil, changedAt: изменено
        )
    }

    private func слушать(_ пойманное: Пойманное) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .togoRemoteDoseChanged, object: nil, queue: nil
        ) { note in
            guard let id = note.userInfo?[RemoteDoseChange.doseIDKey] as? UUID,
                  let закрыта = note.userInfo?[RemoteDoseChange.isClosedKey] as? Bool
            else { return }
            пойманное.закрыта[id] = закрыта
        }
    }

    @Test("Новая чужая доза «дано» подаёт сигнал закрытой дозы")
    func новаяДанаяДоза() throws {
        let context = ModelContext(Persistence.container())
        let пойманное = Пойманное()
        let слушатель = слушать(пойманное)
        defer { NotificationCenter.default.removeObserver(слушатель) }

        let id = UUID()
        SharedDiaryInbox.accept(отметка(id, дана: Date(), изменено: Date()),
                                medication: nil, context: context)

        #expect(пойманное.закрыта[id] == true, """
            чужое «дано» записалось, а напоминания об этой дозе
            никто не снял — у второго человека зазвенит «не отмечена».
            """)
    }

    @Test("Своя открытая доза, закрытая чужой отметкой, подаёт сигнал")
    func слияниеЗакрываетДозу() throws {
        let context = ModelContext(Persistence.container())
        let id = UUID()
        let было = Date().addingTimeInterval(-600)
        SharedDiaryInbox.accept(отметка(id, дана: nil, изменено: было),
                                medication: nil, context: context)

        let пойманное = Пойманное()
        let слушатель = слушать(пойманное)
        defer { NotificationCenter.default.removeObserver(слушатель) }

        SharedDiaryInbox.accept(отметка(id, дана: Date(), изменено: Date()),
                                medication: nil, context: context)

        #expect(пойманное.закрыта[id] == true)
    }

    @Test("Повтор той же отметки сигнала не подаёт")
    func повторМолчит() throws {
        let context = ModelContext(Persistence.container())
        let id = UUID()
        let payload = отметка(id, дана: Date(), изменено: Date())
        SharedDiaryInbox.accept(payload, medication: nil, context: context)

        let пойманное = Пойманное()
        let слушатель = слушать(пойманное)
        defer { NotificationCenter.default.removeObserver(слушатель) }

        SharedDiaryInbox.accept(payload, medication: nil, context: context)
        #expect(пойманное.закрыта[id] == nil, "ничего не поменялось — снимать нечего")
    }
}
