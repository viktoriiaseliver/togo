import Foundation

/// Напоминания об остановках в дороге — для машины, каждые два часа.
///
/// Ставятся, когда поездку заводят или правят, и снимаются, когда её
/// убирают. Правило шага — `TripPlan.остановки`; здесь только очередь.
///
/// Идентификаторы стабильные (`trip-<id>-stop-N`): правка поездки
/// снимает прежние и ставит заново, а не копит вторые.
@MainActor
enum НапоминанияПоездки {

    static func ключи(_ trip: Trip) -> [String] {
        (0..<12).map { "trip-\(trip.id.uuidString)-stop-\($0)" }
    }

    static func обновить(_ trip: Trip, now: Date = Date()) async {
        NotificationCenterService.cancel(ids: ключи(trip))
        guard trip.transport == .car else { return }
        let выезд = Calendar.current.date(minuteOfDay: trip.departureMinuteOfDay, on: trip.startDate)
        let ключи = ключи(trip)
        for (номер, момент) in TripPlan.остановки(выезд: выезд, вДороге: trip.travelHours).enumerated()
        where момент > now && номер < ключи.count {
            let исход = await NotificationCenterService.scheduleTripStop(
                id: ключи[номер], at: момент,
                title: String(localized: "Остановка"),
                body: String(localized: "Два часа в дороге — вода и пять минут походить. Отметь остановку одним тапом на «Сегодня»."))
            if case .отказСистемы = исход {
                UsageLog.note(.record, "tripStop", outcome: .failed)
            }
        }
    }

    static func снять(_ trip: Trip) {
        NotificationCenterService.cancel(ids: ключи(trip))
    }
}
