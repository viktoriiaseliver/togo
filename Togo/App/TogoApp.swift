import SwiftUI
import SwiftData

@main
struct TogoApp: App {
    @State private var appState = AppState()
    @State private var settings = Settings()
    @State private var subscriptions = SubscriptionStore()
    private let container = TogoApp.isUITesting
        ? SeedData.makePreviewContainer()
        : Persistence.container()

    /// UI-тесты запускаются на чистой базе в памяти с демо-собакой:
    /// так тест не зависит от того, что человек уже записал на этом устройстве.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(appState)
                .environment(settings)
                .environment(subscriptions)
                .tint(Token.Action.primary)
                // Тёмной темы в первой версии нет: макет собран под тёплую бумагу,
                // и половинчатая тёмная хуже, чем честно светлая.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

/// Онбординг — 90 секунд и аккаунт не нужен. Пока он не пройден,
/// вкладок нет вовсе: показывать пустую навигацию новому человеку не за чем.
struct AppRoot: View {
    @Environment(Settings.self) private var settings
    @Query private var dogs: [Dog]
    @State private var showsWhatsNew = false

    var body: some View {
        if TogoApp.isUITesting || (settings.onboardingCompleted && dogs.first != nil) {
            RootView()
                // «Что нового» показывается один раз после обновления —
                // и никогда поверх работы на первом запуске.
                .sheet(isPresented: $showsWhatsNew) {
                    NavigationStack { WhatsNewScreen() }
                }
                .task { checkVersion() }
        } else {
            OnboardingFlow()
        }
    }

    private func checkVersion() {
        guard !settings.lastSeenVersion.isEmpty, settings.lastSeenVersion != settings.appVersion else {
            settings.lastSeenVersion = settings.appVersion
            return
        }
        showsWhatsNew = true
        settings.lastSeenVersion = settings.appVersion
    }
}
