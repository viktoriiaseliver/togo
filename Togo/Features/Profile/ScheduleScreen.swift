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
            if !canEdit {
                TGBanner(tone: .waiting, title: "Только чтение",
                         subtitle: "Режим питания меняет тот, кому владелец выдал право на профиль.",
                         systemImage: "lock")
            }
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
