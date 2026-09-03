import SwiftUI
import SwiftData
import CloudKit

/// Приём приглашения в общий дневник.
///
/// Ссылку открывает система, а не приложение: человек нажимает её
/// в мессенджере, iOS проверяет, что он тот, кого звали, и отдаёт нам
/// уже готовое приглашение. Своего кода проверки здесь нет и быть
/// не должно — за это отвечает iCloud.
final class ShareAcceptDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            do {
                try await FamilyShare.accept(metadata)
                SharedDiarySettings.isOn = true
                NotificationCenter.default.post(name: .familyShareAccepted, object: nil)
            } catch {
                log.notice("Приглашение не принялось: \(error.localizedDescription)")
            }
        }
    }
}

extension Notification.Name {
    static let familyShareAccepted = Notification.Name("familyShareAccepted")
}

@main
struct TogoApp: App {
    @UIApplicationDelegateAdaptor(ShareAcceptDelegate.self) private var shareDelegate
    @Environment(\.scenePhase) private var scenePhase
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

    init() {
        // Прогулка теперь переживает закрытие приложения — значит, она
        // переживает и предыдущий тест. Для UI-тестов состояние чистится:
        // иначе второй тест открывает чужую прогулку вместо своей.
        if Self.isUITesting {
            ActiveSessionStore.save(nil)
        }
        Persistence.shared = container
    }

    /// Обмен поднимается, только если его включили руками. Пока он
    /// выключен, приложение ведёт себя ровно так же, как до него.
    @State private var sync: FamilySync?

    private func startSyncIfOn() async {
        guard SharedDiarySettings.isOn, let container else { return }
        if sync == nil { sync = FamilySync(modelContainer: container) }
        await sync?.start()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    AppRoot()
                        .environment(appState)
                        .environment(settings)
                        .environment(subscriptions)
                        .environment(\.familySync, sync)
                        .modelContainer(container)
                } else {
                    StorageFailureScreen()
                }
            }
            // Полная мята — интерактив, и вкладка с шестерёнкой это он:
            // их нажимают. «Сделано» окрашено иначе — плашкой, — потому
            // что галочка выполненного не должна читаться такой же
            // активной, как кнопка.
            .tint(Token.Action.primary)
            // Тема тёмная и единственная: макет собран на чёрном,
            // и светлой пары к нему нет.
            .preferredColorScheme(.dark)
            .task {
                StartupLog.note("интерфейс показан")
                // Журнал действий подрезаем на старте, а не по таймеру:
                // приложение открывают каждый день, и этого достаточно.
                // Отдельной задачей: за две недели там тысячи строк,
                // и разбирать их на главном потоке — это задержка показа
                // первого экрана.
                Task.detached(priority: .utility) { UsageLog.trim() }
            }
            // Пока телефон лежал в кармане, отметку могли поставить
            // кнопкой на живой активности. Перечитываем прогулку,
            // иначе первое же изменение затёрло бы такую отметку.
            .onChange(of: scenePhase) { _, phase in
                // Уходим в фон — дописываем журнал действий на диск:
                // систему никто не спрашивает, когда она выгрузит процесс,
                // а последние действия перед уходом самые ценные.
                if phase != .active { UsageLog.flushNow() }
                if phase == .active {
                    appState.reloadSession()
                    // Пока телефон лежал в кармане, второй человек мог
                    // что-то отметить. Спрашиваем сразу, а не ждём push:
                    // он может и не дойти.
                    Task { await sync?.fetchNow() }
                }
            }
            .task { await startSyncIfOn() }
            .onReceive(NotificationCenter.default.publisher(for: .familyShareAccepted)) { _ in
                Task { await startSyncIfOn() }
            }
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
                    FeedingMigration.run(context: context)
                    WalkLinkStartup.run(context: context)
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
                            .wraps()
                        Spacer(minLength: 0)
                    }
                }
            }

            TGCard {
                TGSectionHeader(title: "что записало приложение при запуске")
                Text(StartupLog.read())
                    .textStyle(AppFont.numeric(12, weight: .regular))
                    .wraps()
                TGExplainer(text: "Здесь только этапы запуска — ничего о собаке. Эти строки помогают понять причину.")
            }

            TGButton(title: "Написать в поддержку", variant: .secondary,
                     size: .medium, systemImage: "envelope") {
                if let url = Contacts.mail(Contacts.support, subject: "Дневник не открылся") {
                    openURL(url)
                }
            }
        }
    }

    private let steps = [
        "Закрыть приложение полностью и открыть заново.",
        "Проверить, что на устройстве есть свободное место.",
        "Если не помогло — переустановить. Дневник вернётся из iCloud или из сохранённого файла.",
    ]
}
