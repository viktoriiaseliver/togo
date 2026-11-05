import SwiftUI

/// Курс завершён — единственный счастливый экран лечения.
///
/// Из хендофа (18g): «Лечение заканчивается — приложение должно уметь
/// заканчиваться вместе с ним. Заодно единственное место, где уместна
/// похвала: она заслуженная и одна.»
///
/// Часть про «не держать вкладку навсегда» **отменена 08.10.2026**
/// (`02c1e88`): вкладку держит право `.seeMedical`. Завершение закрывает
/// схему и напоминания, а не вкладку.
///
/// Похвала считается по записанному: сколько доз дали и какая доля
/// вовремя. Выдуманного процента здесь нет — при нуле отметок цифра
/// не показывается вовсе.
struct CourseFinishSheet: View {
    let dog: Dog
    let summary: TreatmentCourse.Summary
    let farewell: String
    /// Завершить курс лечения — не эпизод: эпизод это серия
    /// инцидентов, и он кончается сам.
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
            // **«Курс», а не «эпизод», и это правка смысла, а не слова.**
            // Эпизод у нас — серия инцидентов (`EpisodeTrigger`:
            // третий жидкий стул или кровь), и заканчивается он сам
            // по тишине. Эта кнопка заканчивает КУРС ЛЕЧЕНИЯ, и соседка
            // под ней говорит ровно это: «Врач продлил — продолжить
            // курс». Два названия одного действия на одном экране,
            // и одно из них звало другую сущность.
            //
            // Найдено вычиткой английского 27.10: перевод «End the
            // episode» верен дословно, а неверен был РУССКИЙ. Ключ
            // «Завершить курс» в каталоге уже есть и переведён
            // на четыре языка — заводить ничего не пришлось.
            TGButton(title: "Завершить курс", systemImage: "checkmark.seal") {
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
        guard summary.dosesGiven > 0 else { return String(localized: "Записи останутся в истории и в отчёте врачу.") }
        let doses = String(localized: "\(summary.dosesGiven) доз")
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
                // Срок — из назначения курса, если врач его назвал
                // (`TreatmentCourse.checkupDelay`, 29.10.2026). Прежде
                // здесь всегда стояли «две недели», при назначенных
                // в рецепте шести.
                //
                // Источник — по тому, ОТКУДА число, а не по его величине
                // (29.10.2026): назначенные врачом ровно 14 дней прежде
                // подписывались «врач обычно смотрит через две недели».
                if let дней = TreatmentCourse.checkupDelayFromPrescription(for: dog) {
                    TGIconRow(symbol: "stethoscope",
                              title: "Контрольный приём",
                              detail: "Срок контроля взят из назначения врача.")
                    TGButton(title: "Напомнить через \(Fmt.days(дней))",
                             variant: .secondary, size: .medium) {
                        назначитьКонтроль(через: дней)
                    }
                } else {
                    let дней = TreatmentCourse.checkupDelayDays
                    TGIconRow(symbol: "stethoscope",
                              title: "Контрольный приём",
                              detail: "Врач обычно смотрит результат через две недели.")
                    TGButton(title: "Напомнить через две недели",
                             variant: .secondary, size: .medium) {
                        назначитьКонтроль(через: дней)
                    }
                }
            }
        }
    }

    private func назначитьКонтроль(через дней: Int) {
        onScheduleCheckup(дней)
        checkupDate = Calendar.current.date(byAdding: .day, value: дней, to: .now)
        Haptics.success()
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
                      detail: "Тумблер «Собака на лечении» в профиле \(dog.displayName) оживит схему обратно.")
        }
    }
}
