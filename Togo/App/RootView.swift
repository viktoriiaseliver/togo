import SwiftUI
import SwiftData

/// Четыре вкладки, и ни одной новой за всё, что добавилось в продукт.
/// «Здоровье» появляется только при включённом лечении — у здоровой собаки
/// медицины на главном нет вовсе.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @State private var selection: Tab = .today

    enum Tab: Hashable { case today, history, health, family }

    private var dog: Dog? { dogs.first }

    /// На «Сегодня» под тостом стоит сетка действий — её высоту надо
    /// перешагнуть. На остальных вкладках хватает высоты таб-бара.
    private var toastInset: CGFloat {
        selection == .today ? 150 : 20
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayScreen()
                .tabItem { Label("Сегодня", systemImage: "sun.horizon") }
                .tag(Tab.today)

            HistoryScreen()
                .tabItem { Label("История", systemImage: "calendar") }
                .tag(Tab.history)

            if dog?.isOnTreatment == true {
                HealthScreen()
                    .tabItem { Label("Здоровье", systemImage: "cross.case") }
                    .tag(Tab.health)
            }

            FamilyScreen()
                .tabItem { Label("Семья", systemImage: "person.2") }
                .tag(Tab.family)
        }
        // Тост подтверждения должен быть виден, а не прятаться за сеткой
        // кнопок: «нажала — и ничего не произошло» — худшее, что может
        // сделать приложение, которое просят отмечать по десять раз в день.
        .overlay(alignment: .bottom) {
            UndoToastView().padding(.bottom, toastInset)
        }
        .onOpenURL(perform: handle)
    }

    /// togo://join/<token> — приглашение в семью из мессенджера.
    private func handle(_ url: URL) {
        guard url.scheme == AppIdentifiers.urlScheme else { return }
        if url.host == "join" { selection = .family }
    }
}

/// Каждая запись отменяется тостом; удаление обратимо 5 секунд.
struct UndoToastView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var appState = appState
        if let toast = appState.undo {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Token.Action.done)
                    .accessibilityHidden(true)
                // Подпись вешаем на текст, а не на всю плашку: иначе она
                // перекрывает собственное имя кнопки «Отменить», и до неё
                // не добраться ни голосом, ни тестом.
                Text(toast.message)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Отменить") { undo(toast) }
                    .textStyle(AppFont.captionEmphasis)
                    .foregroundStyle(Token.Status.overdueText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Token.Surface.card, in: Capsule())
            .shadow(color: Token.Ink.primary.opacity(0.12), radius: 14, y: 4)
            .padding(.horizontal, Token.Spacing.screenPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(5))
                guard appState.undo?.id == toast.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { appState.undo = nil }
            }
        }
    }

    private func undo(_ toast: AppState.UndoToast) {
        if let id = toast.eventID {
            let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
            if let event = try? context.fetch(descriptor).first {
                context.delete(event)
            }
        }
        appState.undo = nil
    }
}
