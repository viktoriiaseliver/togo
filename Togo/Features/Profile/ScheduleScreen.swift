import SwiftUI
import SwiftData

/// Режим дня и питания в профиле. Тот же редактор, что и в онбординге,
/// только сохраняет сразу в собаку.
struct ScheduleScreen: View {
    let dog: Dog

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ScheduleDraft()
    @State private var loaded = false

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            // Плашка была, права не называла — тот же случай, что
            // в `ProfileScreen`, и тем же лечением. «Право на профиль»
            // в списке «Семьи» не значится: там оно зовётся «Менять
            // профиль и уход».
            if !canEdit { ПлашкаПрава(право: .editProfile) }
            ScheduleEditor(draft: $draft)
                .disabled(!canEdit)
        } bottom: {
            if canEdit {
                TGButton(title: "Сохранить") {
                    draft.apply(to: dog)
                    Haptics.success()
                    dismiss()
                }
            }
        }
        .navigationTitle("Режим")
        .cinemaScreen()
        .task {
            guard !loaded else { return }
            draft = ScheduleDraft.from(dog)
            loaded = true
        }
    }
}
