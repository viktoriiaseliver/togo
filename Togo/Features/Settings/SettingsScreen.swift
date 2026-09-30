import SwiftUI
import SwiftData
import StoreKit

/// Настройки. Всё, что Apple ожидает увидеть в приложении с подпиской
/// и с медицинской частью, лежит здесь одним списком.
struct SettingsScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(SubscriptionStore.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Query private var dogs: [Dog]

    @State private var showPaywall = false
    #if DEBUG
    @Environment(\.modelContext) private var context
    @State private var warmupResult: String?
    #endif

    var body: some View {
        List {
            subscriptionSection
            notificationsSection
            dogSection
            dataSection
            legalSection
            aboutSection
            #if DEBUG
            warmupSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .navigationTitle("Настройки")
        // Панель вкладок на настройках не нужна и мешает.
        //
        // Настройки — не вкладка, а место, куда ушли с вкладки. Пока
        // панель видна, у экрана два выхода: «назад» возвращает туда,
        // откуда пришёл, а вкладка молча бросает начатое и уводит
        // в другое место. Эвристика №3, свобода и контроль: путь назад
        // должен быть один и понятный, а не два с разным смыслом.
        .toolbar(.hidden, for: .tabBar)
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
                LabeledContent("Togo Pro", value: "активна")
                NavigationLink("Что будет, если отключить") { DowngradeScreen() }
                Button("Управлять подпиской") { openSubscriptionSettings() }
            } else {
                Button { showPaywall = true } label: {
                    TGListRow(title: "Togo Pro", value: "попробовать", systemImage: "sparkles")
                }
                Button {
                    Task { await store.restore() }
                } label: {
                    HStack {
                        Text("Восстановить покупки")
                        if store.isRestoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isRestoring)
            }
            // Показывать исход обязательно: без этого «покупок нет»
            // и «всё получилось» выглядят одинаково — никак.
            if let outcome = store.lastRestore {
                restoreBanner(outcome)
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

    #if DEBUG
    /// Прогрев зеркала CloudKit. Только отладочная сборка и только руками:
    /// типы `CD_*` заводит зеркало при первой записи, и без этого прогона
    /// одиннадцать моделей из шестнадцати не уезжают в iCloud вовсе.
    /// Подробности и порядок — в `CloudKitSchemaWarmup`.
    private var warmupSection: some View {
        Section {
            Button("Отладка · завести зеркало в iCloud") {
                do {
                    let n = try CloudKitSchemaWarmup.create(in: context)
                    warmupResult = "Создано объектов: \(n). Подожди минуту при живой сети, потом сверь Tools/deploy_cloudkit_schema.sh."
                } catch {
                    warmupResult = "Не сохранилось: \(error.localizedDescription)"
                }
            }
            Button("Отладка · убрать прогрев") {
                do {
                    let n = try CloudKitSchemaWarmup.remove(in: context)
                    warmupResult = "Удалено объектов: \(n). Типы в схеме остаются — они и были целью."
                } catch {
                    warmupResult = "Не удалилось: \(error.localizedDescription)"
                }
            }
            Button("Отладка · что будет при слиянии дубликатов") {
                warmupResult = DuplicateMerge.план(in: context)
            }
            Button("Отладка · слить дубликаты") {
                do { warmupResult = try DuplicateMerge.слить(in: context) }
                catch { warmupResult = "Не вышло: \(error.localizedDescription)" }
            }
            Button("Отладка · что лежит у каждой собаки") {
                warmupResult = CloudKitSchemaWarmup.собаки(in: context)
            }
            Button("Отладка · сколько служебных записей осталось") {
                let остатки = CloudKitSchemaWarmup.остатки(in: context)
                let всего = остатки.values.reduce(0, +)
                warmupResult = всего == 0
                    ? "Служебных записей прогрева не осталось: 0. Это замер, а не «вроде бы»."
                    : "Осталось \(всего): "
                        + остатки.sorted { $0.key < $1.key }
                            .map { "\($0.key) × \($0.value)" }.joined(separator: ", ")
            }
            if let warmupResult {
                Text(warmupResult).textStyle(AppFont.caption)
            }
        } header: {
            Text("отладка")
        } footer: {
            Text("Этого раздела нет в сборке для App Store. Он заводит по одному объекту каждого типа с датой 1 января 2001 года, чтобы CloudKit создал зеркала; потом их убирает.")
        }
    }
    #endif

    /// Итог восстановления человеческими словами.
    ///
    /// «Покупок не нашлось» — не сбой, поэтому тон спокойный: чаще всего
    /// человек просто не покупал или вошёл под другим Apple ID.
    @ViewBuilder
    private func restoreBanner(_ outcome: SubscriptionStore.Restore) -> some View {
        switch outcome {
        case .restored:
            TGBanner(tone: .done, title: "Подписка вернулась",
                     systemImage: "checkmark.circle")
        case .nothingFound:
            TGBanner(tone: .neutral, title: "Покупок не нашлось",
                     subtitle: "На этом Apple ID подписки Togo нет. Если покупка была с другого — войди в него в App Store.",
                     systemImage: "magnifyingglass")
        case .failed:
            TGBanner(tone: .alarm, title: "Не получилось",
                     subtitle: store.lastError.map { .готовая($0) },
                     systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: Уведомления

    private var notificationsSection: some View {
        @Bindable var settings = settings
        return Section {
            NavigationLink {
                NotificationSettingsScreen()
            } label: {
                LabeledContent("Утренняя сводка", value: Fmt.clock(minuteOfDay: settings.briefHour * 60))
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
                // Без подписки вторая и следующие собаки закрыты
                // (`AppState.закрыта`) — и здесь тоже, иначе профиль
                // закрытой собаки открывался бы в обход замка.
                if appState.закрыта(dog, среди: dogs) {
                    Button { showPaywall = true } label: {
                        LabeledContent(dog.name) {
                            Image(systemName: "lock.fill").accessibilityLabel("в Pro")
                        }
                    }
                } else {
                    NavigationLink {
                        ProfileScreen(dog: dog)
                    } label: {
                        LabeledContent(dog.name, value: Fmt.weight(dog.weightKg))
                    }
                }
            }
            // Та же дверь, что в списке собак: `canAddDog`.
            if store.canAddDog(existing: dogs.count) {
                NavigationLink("Добавить собаку") { DogEditorScreen() }
            } else {
                Button("Добавить вторую собаку") { showPaywall = true }
            }
        } header: {
            Text(dogs.count > 1 ? "собаки" : "собака")
        } footer: {
            Text(dogs.isEmpty
                 ? "Без собаки приложению нечего считать — начни с неё."
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
            Text("Всё считается на телефоне. Аккаунт не нужен, серверов у нас нет. Переустановку дневник переживает через iCloud или файл.")
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

/// Час сводки и тихие часы — единственные ручки, которые человек реально крутит.
struct NotificationSettingsScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @State private var status: String?

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Picker("Час сводки", selection: $settings.briefHour) {
                    ForEach(5...12, id: \.self) { hour in
                        Text(Fmt.clock(minuteOfDay: hour * 60)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.briefHour) { _, _ in
                    Task { await ReminderScheduler.scheduleBrief(dog: appState.activeDog(from: dogs), settings: settings) }
                }
            } header: {
                Text("утренняя сводка")
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
        case .authorized, .provisional, .ephemeral: String(localized: "разрешены")
        case .denied: String(localized: "запрещены")
        case .notDetermined: String(localized: "ещё не спрашивали")
        @unknown default: String(localized: "неизвестно")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
