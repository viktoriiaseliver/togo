import Foundation
import SwiftData

/// Приёмы препаратов по расписанию.
///
/// До этого вся медицинская часть была мертва: схему завести можно было,
/// а отметок приёма никто не создавал. А от них зависит всё остальное —
/// окно натощак считается от **фактической** отметки, защита от двойной
/// дозы смотрит на отметки, лестница эскалации тоже. Схема была, машинерия
/// вокруг неё не работала ни разу.
nonisolated enum DoseScheduler {
    /// Завести отметки на день, если их ещё нет.
    ///
    /// Делается лениво, при открытии экрана: плодить записи на год вперёд
    /// незачем, а на день — ровно столько, сколько нужно эскалации,
    /// чтобы понимать, что дозу пропустили.
    @MainActor
    @discardableResult
    static func ensureDoses(for dog: Dog, on day: Date = Date(), context: ModelContext) -> Int {
        guard dog.isOnTreatment else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        var created = 0

        for medication in dog.medications where !medication.isPaused {
            for minute in medication.times.sorted() {
                let scheduled = startOfDay.addingTimeInterval(Double(minute) * 60)
                let exists = medication.doses.contains {
                    calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
                }
                guard !exists else { continue }

                let dose = DoseRecord(scheduledAt: scheduled)
                dose.medication = medication
                context.insert(dose)
                created += 1
            }
        }

        if created > 0 { try? context.save() }
        return created
    }

    /// Отметить приём. Возвращает отметку, чтобы экран мог показать,
    /// когда закончится окно натощак.
    @MainActor
    @discardableResult
    static func markGiven(
        _ medication: Medication,
        scheduledAt scheduled: Date,
        by person: String,
        at now: Date = Date(),
        context: ModelContext
    ) -> DoseRecord? {
        let calendar = Calendar.current
        let dose = medication.doses.first {
            calendar.isDate($0.scheduledAt, equalTo: scheduled, toGranularity: .minute)
        } ?? {
            let new = DoseRecord(scheduledAt: scheduled)
            new.medication = medication
            context.insert(new)
            return new
        }()

        // Дважды одну дозу не отмечаем: это и есть защита от двойной дозы.
        guard dose.givenAt == nil else { return dose }

        dose.givenAt = now
        dose.givenBy = person
        try? context.save()
        return dose
    }

    /// Окно натощак: когда снова можно кормить.
    ///
    /// Считается от фактической отметки, а не от расписания: таблетку дали
    /// в 07:12, а не в 07:00, и еда мешает всасыванию именно с этого момента.
    @MainActor
    static func fastingEnds(for dog: Dog, at now: Date = Date()) -> (until: Date, medication: String, givenAt: Date)? {
        guard dog.isOnTreatment else { return nil }

        for medication in dog.medications where medication.fastingMinutes > 0 && !medication.isPaused {
            guard let dose = medication.doses
                .filter({ $0.isGiven })
                .max(by: { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }),
                  let givenAt = dose.givenAt else { continue }

            let ends = givenAt.addingTimeInterval(Double(medication.fastingMinutes) * 60)
            if now < ends {
                return (until: ends, medication: medication.name, givenAt: givenAt)
            }
        }
        return nil
    }
}
