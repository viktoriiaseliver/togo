import SwiftUI

/// Курс завершён — единственный счастливый экран лечения.
///
/// Из хендофа (18g): «Лечение заканчивается — приложение должно уметь
/// заканчиваться вместе с ним, а не держать вкладку «Здоровье» навсегда.
/// Заодно единственное место, где уместна похвала: она заслуженная
/// и одна.»
///
/// Похвала считается по записанному: сколько доз дали и какая доля
/// вовремя. Выдуманного процента здесь нет — при нуле отметок цифра
/// не показывается вовсе.
struct CourseFinishSheet: View {
    let dog: Dog
    let summary: TreatmentCourse.Summary
    let farewell: String
    /// Завершить эпизод.
    var onFinish: () -> Void
    /// Врач продлил — курс продолжается.
    var onContinue: (() -> Void)?
    /// Завести дело «контрольный приём».
    var onScheduleCheckup: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var checkupDate: Date?

    var body: some View {
        TGSheet(title: .готовая(summary.headline), subtitle: .готовая(praise)) {
            if summary.dosesGiven > 0 { numbers }
            next
            consequences
        } footer: {
            TGButton(title: "Завершить эпизод", systemImage: "checkmark.seal") {
                onFinish()
                dismiss()
            }
            TGButton(title: "Врач продлил — продолжить курс",
                     variant: .secondary, size: .medium) {
                onContinue?()
                dismiss()
            }
        }
        .presentationDetents([.large])
    }

    /// «82 дозы, 94% вовремя — вы справились вдвоём.»
    private var praise: String {
        guard summary.dosesGiven > 0 else { return "Записи остаются, вкладка прячется." }
        let doses = Fmt.plural(summary.dosesGiven, "доза", "дозы", "доз")
        guard let share = summary.onTimeShare else { return doses }
        return "\(doses), \(Int((share * 100).rounded()))% вовремя"
    }

    private var numbers: some View {
        TGCard(spacing: 0) {
            TGListRow(title: "Дозы отмечены", value: "\(summary.dosesGiven)", accessory: .none)
            if let share = summary.onTimeShare {
                TGDivider()
                TGListRow(title: "Вовремя", value: "\(Int((share * 100).rounded()))%",
                          accessory: .none)
            }
            if summary.skipped > 0 {
                TGDivider()
                TGListRow(title: "Пропущено осознанно", value: "\(summary.skipped)",
                          accessory: .none)
                TGExplainer(text: "Пропуск — тоже запись: врач спросит именно про него.")
            }
        }
    }

    /// Что дальше. Контрольный приём — единственное, что переживает курс.
    ///
    /// Не фраза на экране, а дело в уходе: иначе про приём вспоминают
    /// в день приёма.
    private var next: some View {
        TGCard {
            TGSectionHeader(title: "что дальше")
            if let checkupDate {
                TGIconRow(symbol: "checkmark.circle",
                          title: "Контрольный приём \(Fmt.shortDay(checkupDate))",
                          detail: "Напомним за три дня. Дату поменяешь в уходе.")
            } else {
                TGIconRow(symbol: "stethoscope",
                          title: "Контрольный приём",
                          detail: "Врач обычно смотрит результат через две недели.")
                TGButton(title: "Напомнить через две недели",
                         variant: .secondary, size: .medium) {
                    onScheduleCheckup(TreatmentCourse.checkupDelayDays)
                    checkupDate = Calendar.current.date(
                        byAdding: .day, value: TreatmentCourse.checkupDelayDays, to: .now)
                    Haptics.success()
                }
            }
        }
    }

    private var consequences: some View {
        TGCard {
            TGSectionHeader(title: "что изменится")
            TGExplainer(text: .готовая(farewell))
            TGIconRow(symbol: "tray.full",
                      title: "Записи уйдут в архив",
                      detail: "История, вес и отчёт врачу остаются на месте.")
            TGIconRow(symbol: "arrow.uturn.backward",
                      title: "Вернуть — один тап",
                      detail: "Тумблер «Собака на лечении» в профиле \(dog.name) оживит схему обратно.")
        }
    }
}
