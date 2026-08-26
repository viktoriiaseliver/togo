import SwiftUI
import SwiftData

@main
struct TogoApp: App {
    @State private var appState = AppState()
    @State private var settings = Settings()
    @State private var subscriptions = SubscriptionStore()
    /// Может быть nil: если хранилище не открылось, приложение показывает
    /// экран с объяснением, а не исчезает с экрана без единого слова.
    private let container: ModelContainer? = TogoApp.isUITesting
        ? SeedData.makePreviewContainer()
        : Persistence.appContainer()

    /// UI-тесты запускаются на чистой базе в памяти с демо-собакой:
    /// так тест не зависит от того, что человек уже записал на этом устройстве.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    AppRoot()
                        .environment(appState)
                        .environment(settings)
                        .environment(subscriptions)
                        .modelContainer(container)
                } else {
                    StorageFailureScreen()
                }
            }
            .tint(Token.Action.primary)
            // Тёмной темы в первой версии нет: макет собран под тёплую бумагу,
            // и половинчатая тёмная хуже, чем честно светлая.
            .preferredColorScheme(.light)
            .task { StartupLog.note("интерфейс показан") }
        }
    }
}

/// Онбординг — 90 секунд и аккаунт не нужен. Пока он не пройден,
/// вкладок нет вовсе: показывать пустую навигацию новому человеку не за чем.
struct AppRoot: View {
    @Environment(Settings.self) private var settings
    @Environment(\.modelContext) private var context
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
                .task {
                    checkVersion()
                    // Уход у тех, кто ставил приложение до переделки, чинится
                    // один раз и молча: человек не должен ничего править руками.
                    let fixed = CareMigration.run(context: context)
                    if fixed > 0 { StartupLog.note("уход починен: \(fixed)") }
                    Persistence.removeLegacyStoreIfSafe(context: context)
                }
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


/// Хранилище не открылось. Экран вместо молчаливого падения: человек
/// должен понимать, что случилось, и иметь что нажать.
struct StorageFailureScreen: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        TGScreen(title: "Дневник не открылся") {
            TGBanner(tone: .alarm, title: "Не удалось открыть хранилище",
                     subtitle: "Это не потеря данных: записи на месте, но приложение сейчас не может до них добраться.",
                     systemImage: "externaldrive.badge.exclamationmark")

            TGCard {
                Text("Что попробовать").textStyle(AppFont.cardTitle)
                ForEach(steps, id: \.self) { step in
                    HStack(alignment: .top, spacing: Token.Space.s8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Token.Ink.faint)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        Text(step)
                            .textStyle(AppFont.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            TGCard {
                TGSectionHeader(title: "что записало приложение при запуске")
                Text(StartupLog.read())
                    .textStyle(AppFont.numeric(12, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
                TGExplainer(text: "Здесь только этапы запуска — ничего о собаке. Эти строки помогают понять причину.")
            }

            TGButton(title: "Написать в поддержку", variant: .secondary,
                     size: .medium, systemImage: "envelope") {
                if let url = URL(string: "mailto:support@togo.app?subject=Дневник%20не%20открылся") {
                    openURL(url)
                }
            }
        }
    }

    private let steps = [
        "Закрыть приложение полностью и открыть заново.",
        "Проверить, что на устройстве есть свободное место.",
        "Если не помогло — переустановить. Дневник вернётся из iCloud или из файла бэкапа.",
    ]
}
