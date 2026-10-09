import SwiftUI
import SwiftData

/// Запись попытки по навыку процедуры.
///
/// **Лист не закрывается после попытки нарочно.** Процедуру пробуют
/// по нескольку раз подряд — дать лапу, забрать, дать снова, — и лист,
/// который захлопывается после каждой, заставлял бы открывать его
/// пять раз, чтобы записать пять попыток.
///
/// Здесь же живёт удаление. До 28.09 оно было **единственным** действием
/// экрана и висело на самом лёгком жесте: тап по строке предлагал убрать
/// навык. Разрушительное действие не должно быть самым доступным.
struct SkillAttemptSheet: View {
    let skill: ProcedureSkill
    /// Закрыть лист. `true` — человек попросил удалить навык.
    var onClose: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// Чем была последняя попытка — чтобы её можно было снять.
    /// Пусто, пока в этом листе ничего не записывали: отменять чужую
    /// попытку из прошлого раза нельзя, мы не знаем, какой она была.
    @State private var последняя: Bool?

    var body: some View {
        TGSheet(title: .готовая(skill.title), subtitle: .готовая(skill.detail)) {
            TGCard {
                HStack(spacing: 0) {
                    TGStat(value: "\(skill.successes)", caption: "получилось")
                    TGStat(count: skill.attempts,
                           сЧислом: String(localized: "\(skill.attempts) попыток"))
                }
                TGDivider()
                Text(объяснение)
                    .textStyle(AppFont.caption)
                    .wraps()
            }

            TGButton(title: "Получилось", variant: .primary, systemImage: "checkmark") {
                записать(success: true)
            }
            TGButton(title: "Не получилось", variant: .secondary, systemImage: "xmark") {
                записать(success: false)
            }

            if let последняя {
                TGButton(title: "Отменить последнюю", variant: .secondary, size: .medium,
                         systemImage: "arrow.uturn.backward") {
                    снять(последняя)
                }
            }

            TGExplainer(text: "Собака в любой момент может уйти. Ушла — значит, задача была слишком сложной, а не собака плохая. Это тоже попытка, и её стоит записать: по ней видно, что шаг надо упростить.")

            TGButton(title: "Убрать навык", variant: .destructive, size: .medium,
                     systemImage: "trash") {
                onClose(true)
                dismiss()
            }
        }
        .onDisappear { onClose(false) }
    }

    /// Что сказать про счёт.
    ///
    /// «Не начинали» и «учится» без объяснения читаются оценкой собаки.
    /// Здесь говорится про счёт попыток: чего ещё не хватает, чтобы
    /// приложение вообще имело право что-то сказать.
    private var объяснение: String {
        let осталось = SkillProgress.attemptsUntilVerdict(attempts: skill.attempts)
        if skill.attempts == 0 {
            return String(localized: "Попыток пока нет. Приложение скажет, получается ли, после \(SkillProgress.minimumAttempts) попыток — раньше это была бы догадка.")
        }
        if осталось > 0 {
            return String(localized: "Ещё \(осталось) попыток, и станет видно. Получается — это 4 раза из 5, как и у шага обучения.")
        }
        return String(localized: "Сейчас: \(skill.status.title). Получается — это 4 раза из 5.")
    }

    private func записать(success: Bool) {
        skill.record(success: success)
        guard сохранить(иначе: { skill.undoAttempt(wasSuccess: success) }) else { return }
        последняя = success
        Haptics.success()
    }

    private func снять(_ wasSuccess: Bool) {
        skill.undoAttempt(wasSuccess: wasSuccess)
        guard сохранить(иначе: { skill.record(success: wasSuccess) }) else { return }
        последняя = nil
        Haptics.tap()
    }

    /// Не сохранилось — не говорим «записано» и возвращаем счёт назад.
    ///
    /// Откат руками, а не `rollback()`: на iOS 26 он снимает признак
    /// изменений и не возвращает значений. Это у Togo записано ценой
    /// отметки дозы, которая «сохранилась» и пропала.
    private func сохранить(иначе вернуть: () -> Void) -> Bool {
        guard context.persist(otherwise: вернуть) else {
            Haptics.warning()
            appState.showFailure("Не записалось · нажми ещё раз")
            return false
        }
        return true
    }
}
