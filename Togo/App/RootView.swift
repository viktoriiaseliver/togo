import SwiftUI
import SwiftData

/// Четыре вкладки, и ни одной новой за всё, что добавилось в продукт.
/// «Здоровье» появляется только при включённом лечении — у здоровой собаки
/// медицины на главном нет вовсе.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @State private var selection: Tab = .today

    enum Tab: Hashable { case today, dog, history, health, family }

    private var dog: Dog? { appState.activeDog(from: dogs) }

    /// На «Сегодня» под тостом стоит сетка действий — её высоту надо
    /// перешагнуть. На остальных вкладках хватает высоты таб-бара.
    private var toastInset: CGFloat {
        selection == .today ? 150 : 20
    }

    /// Переключить вкладку снаружи — например из шторки «Ещё», которая
    /// больше не строит навигацию сама.
    func show(_ tab: Tab) { selection = tab }

    var body: some View {
        TabView(selection: $selection) {
            TodayScreen(onOpenDog: { selection = .dog })
                .tabItem { Label("Сегодня", systemImage: "sun.horizon") }
                .tag(Tab.today)

            DogTab()
                .tabItem { Label(dog?.name ?? "Собака", systemImage: "pawprint") }
                .tag(Tab.dog)

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
        // Курс завершили, стоя на «Здоровье»: вкладка исчезает вместе
        // с выбором, и TabView остаётся на пустом месте. Возвращаем
        // человека на «Сегодня» сами.
        .onChange(of: dog?.isOnTreatment ?? false) { _, isOnTreatment in
            if !isOnTreatment, selection == .health { selection = .today }
        }
        .onChange(of: selection) { _, tab in
            UsageLog.note(.tab, String(describing: tab), on: screen(for: tab))
        }
        .onOpenURL(perform: handle)
    }

    /// Вкладка — это и есть экран: журнал действий не должен считать
    /// переключение вкладки действием на предыдущей.
    private func screen(for tab: Tab) -> UsageLog.Screen {
        switch tab {
        case .today: .today
        case .dog: .profile
        case .history: .history
        case .health: .health
        case .family: .family
        }
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
                    .wraps()
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
        switch toast.action {
        case .removeCreated(let id):
            if let event = event(id) {
                UsageLog.note(.undo, event.kind.rawValue)
                context.delete(event)
            }
        case .restoreDeleted(let ids):
            UsageLog.note(.undo, "restore")
            // Прогулка возвращается вместе с отметками — тем же составом,
            // каким уходила.
            for id in ids {
                guard let event = event(id) else { continue }
                event.deletedAt = nil
                event.deletedBy = nil
            }
        case nil:
            break
        }
        try? context.save()
        appState.undo = nil
    }

    private func event(_ id: UUID) -> LogEvent? {
        let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
