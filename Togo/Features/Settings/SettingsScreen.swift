import SwiftUI
import SwiftData
import StoreKit

/// Настройки. Всё, что Apple ожидает увидеть в приложении с подпиской
/// и с медицинской частью, лежит здесь одним списком.
struct SettingsScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(SubscriptionStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Query private var dogs: [Dog]

    @State private var showPaywall = false

    var body: some View {
        List {
            subscriptionSection
            notificationsSection
            dogSection
            dataSection
            legalSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .navigationTitle("Настройки")
        .usageScreen(.settings)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallScreen() }
        }
    }

    // MARK: Подписка

    private var subscriptionSection: some View {
        Section {
            if store.isPro {
                LabeledContent("Того Pro", value: "активна")
                NavigationLink("Что будет, если отключить") { DowngradeScreen() }
                Button("Управлять подпиской") { openSubscriptionSettings() }
            } else {
                Button { showPaywall = true } label: {
                    TGListRow(title: "Того Pro", value: "попробовать", systemImage: "sparkles")
                }
                Button("Восстановить покупки") { Task { await store.restore() } }
            }
            #if DEBUG
            Toggle("Отладка · включить Pro", isOn: Binding(
                get: { store.debugOverride ?? store.isPro },
                set: { store.debugOverride = $0 }
            ))
            #endif
        } header: {
            Text("подписка")
        } footer: {
            Text("Окно натощак, защита от двойной дозы, «как попросил» и строка про наказание бесплатны навсегда и в подписку не входят.")
        }
    }

    // MARK: Уведомления

    private var notificationsSection: some View {
        @Bindable var settings = settings
        return Section {
            NavigationLink {
                NotificationSettingsScreen()
            } label: {
                LabeledContent("Утренний бриф", value: Fmt.clock(minuteOfDay: settings.briefHour * 60))
            }
            LabeledContent("Тихие часы") {
                Text("\(Fmt.clock(minuteOfDay: settings.quietHoursStart * 60)) — \(Fmt.clock(minuteOfDay: settings.quietHoursEnd * 60))")
            }
            Toggle("Отклик при записи", isOn: $settings.haptics)
            NavigationLink("Язык") { LanguageScreen() }
        } header: {
            Text("что прерывает")
        } footer: {
            Text("Прерывают только доза по часам, окно натощак и лестница эскалации. Всё остальное придёт утром, одним сообщением.")
        }
    }

    // MARK: Собака

    private var dogSection: some View {
        Section {
            ForEach(dogs) { dog in
                NavigationLink {
                    ProfileScreen(dog: dog)
                } label: {
                    LabeledContent(dog.name, value: Fmt.weight(dog.weightKg))
                }
            }
            if dogs.isEmpty || store.isPro {
                NavigationLink("Добавить собаку") { DogEditorScreen() }
            } else {
                Button("Добавить вторую собаку") { showPaywall = true }
            }
        } header: {
            Text(dogs.count > 1 ? "собаки" : "собака")
        } footer: {
            Text(dogs.isEmpty
                 ? "Без собаки приложению нечего считать — начните с неё."
                 : "Удалить собаку можно в её профиле, внизу.")
        }
    }

    // MARK: Данные

    private var dataSection: some View {
        Section {
            NavigationLink("Перенос и восстановление") { BackupScreen() }
            NavigationLink("Данные и приватность") { DataPrivacyScreen() }
            NavigationLink("Журнал действий") { UsageLogScreen() }
        } header: {
            Text("данные")
        } footer: {
            Text("Всё считается на телефоне. Аккаунт не нужен, записи не уходят на наши серверы. Переустановку дневник переживает через iCloud или через файл.")
        }
    }

    // MARK: Правовое

    private var legalSection: some View {
        Section("правовое") {
            NavigationLink("Политика конфиденциальности") { PrivacyPolicyScreen() }
            NavigationLink("Условия использования") { TermsScreen() }
            NavigationLink("Приложение — не медицинское устройство") { MedicalDisclaimerScreen() }
            NavigationLink("Открытый код и благодарности") { AcknowledgementsScreen() }
        }
    }

    // MARK: О приложении

    private var aboutSection: some View {
        Section {
            NavigationLink("Как это работает") { HowItWorksScreen() }
            NavigationLink("Метка у двери") { DoorTagScreen() }
            Button("Пройти онбординг заново") { replayOnboarding() }
            NavigationLink("Что нового") { WhatsNewScreen() }
            NavigationLink("Поддержка") { SupportScreen() }
            Button("Оценить приложение") { requestReview() }
            NavigationLink {
                AboutScreen()
            } label: {
                LabeledContent("Версия", value: "\(settings.appVersion) (\(settings.buildNumber))")
            }
            #if DEBUG
            NavigationLink("Библиотека компонентов") { ComponentGallery() }
            #endif
        } header: {
            Text("о приложении")
        }
    }

    /// Онбординг можно пройти заново: данные при этом не трогаем —
    /// человек просто перечитывает то, что ему рассказали один раз.
    private func replayOnboarding() {
        settings.onboardingCompleted = false
    }

    private func openSubscriptionSettings() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url)
    }
}

/// Час брифа и тихие часы — единственные ручки, которые человек реально крутит.
struct NotificationSettingsScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @State private var status: String?

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Picker("Час брифа", selection: $settings.briefHour) {
                    ForEach(5...12, id: \.self) { hour in
                        Text(Fmt.clock(minuteOfDay: hour * 60)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.briefHour) { _, _ in
                    Task { await ReminderScheduler.scheduleBrief(dog: appState.activeDog(from: dogs), settings: settings) }
                }
            } header: {
                Text("утренний бриф")
            } footer: {
                Text("Груминг, антипаразитарка, прививки и взвешивание приходят одним сообщением в этот час. Отложенное дважды в нём подсвечивается, но в тревогу не переходит.")
            }

            Section {
                Picker("Начало", selection: $settings.quietHoursStart) {
                    ForEach(20...23, id: \.self) { Text(Fmt.clock(minuteOfDay: $0 * 60)).tag($0) }
                }
                Picker("Конец", selection: $settings.quietHoursEnd) {
                    ForEach(5...9, id: \.self) { Text(Fmt.clock(minuteOfDay: $0 * 60)).tag($0) }
                }
            } header: {
                Text("тихие часы")
            } footer: {
                Text("В тихие часы приложение не спрашивает результат выхода — соберёт утром одной карточкой.")
            }

            Section {
                if let status {
                    LabeledContent("Разрешение", value: status)
                } else {
                    TGLoading(message: "Спрашиваю систему…", isCompact: true)
                }
                Button("Открыть настройки iOS") { openSystemSettings() }
            } footer: {
                Text("Дневник работает целиком и без уведомлений: они нужны только дозе, окну натощак и эскалации.")
            }
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .task { status = await readableStatus() }
    }

    private func readableStatus() async -> String {
        switch await NotificationCenterService.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: "разрешены"
        case .denied: "запрещены"
        case .notDetermined: "ещё не спрашивали"
        @unknown default: "неизвестно"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
