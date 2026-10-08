import SwiftUI
import SwiftData
import CloudKit

/// Приём приглашения в общий дневник.
///
/// Ссылку открывает система, а не приложение: человек нажимает её
/// в мессенджере, iOS проверяет, что он тот, кого звали, и отдаёт нам
/// уже готовое приглашение. Своего кода проверки здесь нет и быть
/// не должно — за это отвечает iCloud.
///
/// **Приглашение приходит на делегат СЦЕНЫ, а не приложения.** У
/// приложения со сценами — а SwiftUI-приложение со сценами всегда —
/// UIKit зовёт `windowScene(_:userDidAcceptCloudKitShareWith:)`.
/// Одноимённый метод `UIApplicationDelegate` не зовётся вовсе, и пока
/// обработчик стоял на нём, гость нажимал ссылку, а не происходило
/// ничего: без принятого приглашения не работало и всё остальное.
///
/// Делегат сцены подключается единственным способом, который у
/// SwiftUI есть, — `configurationForConnecting`. Своего окна он
/// не заводит: окно по-прежнему строит `WindowGroup`.
final class ShareAcceptDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil,
                                                 sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareAcceptSceneDelegate.self
        return configuration
    }
}

/// Та самая дверь, в которую стучится система с принятым приглашением.
///
/// Дверей две, и обе нужны. Приложение уже открыто — приходит
/// `windowScene(_:userDidAcceptCloudKitShareWith:)`. Приложение
/// запускает сама ссылка — приглашение лежит в `ConnectionOptions`
/// первой сцены, и метод выше в этом случае может не прийти вовсе.
/// Повторный приём безвреден: `ShareAcceptance` помнит, что уже принял.
final class ShareAcceptSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptance.accept(metadata)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.accept(metadata)
        }
    }
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
        ? SeedData.makePreviewContainer(TogoApp.uiTestingScenario)
        : Persistence.appContainer()



    /// UI-тесты запускаются на чистой базе в памяти с демо-собакой:
    /// так тест не зависит от того, что человек уже записал на этом устройстве.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    /// Какой демо-набор просит тест: `-Сценарий silence`.
    ///
    /// Без аргумента — обычный день, как было. Незнакомое имя **валит
    /// запуск нарочно**: молча подставить обычный день значит дать тесту
    /// снять не то состояние и назвать это успехом. Набор, которому нечего
    /// проверять, молчит так же, как набор, у которого всё хорошо.
    static var uiTestingScenario: SeedData.Scenario {
        let args = ProcessInfo.processInfo.arguments
        guard let место = args.firstIndex(of: "-Сценарий") else { return .today }
        let имя = args.indices.contains(место + 1) ? args[место + 1] : ""
        guard let сценарий = SeedData.Scenario(rawValue: имя) else {
            fatalError("неизвестный сценарий демо-базы: «\(имя)»")
        }
        return сценарий
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
            // ТЕМУ ВЫБИРАЕТ СИСТЕМА — строки `.preferredColorScheme(.dark)`
            // здесь больше нет, и её отсутствие важнее любой строки,
            // которую можно было бы поставить вместо.
            //
            // **Светлая тема существовала в токенах и не доходила
            // до экрана.** 07.10.2026 заведены четыре режима — 24 примитива,
            // 57 ссылок на 27 общих цветов, 19 пар контраста измерены
            // в каждом из четырёх, — а этот модификатор прибивал схему
            // к тёмной. Приложение показывало тёмное при любой настройке
            // телефона.
            //
            // > **Значение верное, вызов бессильный.** Токены верны,
            // > сторож контраста зелен, инструкция тестировщику зовёт
            // > переключать тему — и ни одно из трёх не смотрит на то,
            // > СПРАШИВАЕТ ли приложение систему.
            //
            // Комментарий, который здесь стоял, был верен в день
            // написания: «макет собран на чёрном, и светлой пары к нему
            // нет». Светлая пара появилась, комментарий остался — и держал
            // код. Сторож `ТемаНеПрибитаTests` краснеет, если модификатор
            // вернётся.
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
            // Одно место на оба исхода приёма приглашения, и говорят
            // они разное.
            //
            // Пока отказ кончался записью в журнал, человек не узнавал
            // ничего: приложение открывалось обычным, и гость считал,
            // что вошёл. Успех при этом тоже молчал — «вы в общем
            // дневнике» ему никто не говорил, а чей это дневник,
            // не говорили тем более.
            //
            // Обмен поднимается ТОЛЬКО на успехе: на отказе поднимать
            // нечего, зона не наша.
            .onReceive(NotificationCenter.default.publisher(for: .familyShareAccepted)) { _ in
                let исход = ShareAcceptance.исход
                if исход?.принято_ли != false {
                    Task { await startSyncIfOn() }
                }
                if let исход {
                    appState.showUndo(исход.текст)
                    ShareAcceptance.исходПрочитан()
                }
            }
        }
    }
}

/// Онбординг — 90 секунд и аккаунт не нужен. Пока он не пройден,
/// вкладок нет вовсе: показывать пустую навигацию новому человеку не за чем.
struct AppRoot: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var dogs: [Dog]
    @Query private var members: [FamilyMember]
    @State private var showsWhatsNew = false

    var body: some View {
        // Собаки может не быть намеренно: на шаге «Кто у тебя живёт» есть
        // «Пока без собаки». Раньше здесь стояло `&& dogs.first != nil`,
        // и пропуск не удержался бы — приложение вернуло бы в онбординг.
        // Предохранителем от пустого хранилища это условие тоже больше
        // не служит: сломанную базу ловит `Persistence.openContainer`
        // и показывает «Дневник не открылся».
        if TogoApp.isUITesting || settings.onboardingCompleted {
            RootView()
                // «Что нового» показывается один раз после обновления —
                // и никогда поверх работы на первом запуске.
                .sheet(isPresented: $showsWhatsNew) {
                    NavigationStack { WhatsNewScreen() }
                }
                .task {
                    checkVersion()
                    // Роль и права берутся из своей карточки при каждом
                    // запуске. Без этого выданная роль не применялась
                    // нигде: `adopt` звали только при ручной правке
                    // карточки, а до тех пор на телефоне действовал
                    // владелец по умолчанию.
                    appState.adoptMe(from: members)
                    // Уход у тех, кто ставил приложение до переделки, чинится
                    // один раз и молча: человек не должен ничего править руками.
                    let fixed = CareMigration.run(context: context)
                    FeedingMigration.run(context: context)
                    WalkLinkStartup.run(context: context)
                    if fixed > 0 { StartupLog.note("уход починен: \(fixed)") }
                    // Откуда взялась собака — запись на будущее. 23.09
                    // дубликат появился, а причину было нечем найти:
                    // крошки за тот час затёрлись. Теперь прибавление
                    // и пропажа называются в момент, когда случились.
                    DogOrigin.проверить(in: context)
                    // Перепись безымянных — ПОСЛЕ переписи источников:
                    // та печатает по каждой собаке источник, час
                    // создания и счёт записей.
                    //
                    // Ничего не удаляет. Решение 07.10.2026: пустые
                    // записи не показываем (`Dog.canBeShown`), а не
                    // стираем — «не показать» самоисправляется, когда
                    // доедет кличка, а удаление необратимо и уносит
                    // одиннадцать каскадов.
                    let безымянных = NamelessDogAudit.перепись(in: context)
                    if безымянных > 0 { StartupLog.note("безымянных записей: \(безымянных)") }
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
///
/// Письмо здесь — последняя дверь: дневник не открылся, и больше
/// в приложении делать нечего. `mailto:` на телефоне без настроенной
/// почты не открывается ничем — человек получает системный алерт,
/// а за ним пусто. Поэтому «не открылось» обрабатывается, а адрес
/// уходит в буфер: та же починка, что на экране поддержки, и по тому же
/// правилу — правка, меняющая читаемое, применяется ко всем поверхностям,
/// где та же строка живёт.
struct StorageFailureScreen: View {
    @Environment(\.openURL) private var openURL
    @State private var копияАдреса: String?

    /// Крошки запуска читаются ОДИН раз: по ним же решается, можно ли
    /// советовать переустановку, и два чтения разошлись бы, если файл
    /// дописали между ними.
    private let журналЗапуска = StartupLog.read()

    private var возврат: StorageFailureAdvice.Возврат {
        StorageFailureAdvice.возврат(журналЗапуска: журналЗапуска)
    }

    var body: some View {
        TGScreen(title: "Дневник не открылся") {
            TGBanner(tone: .alarm, title: "Не удалось открыть хранилище",
                     subtitle: .готовая(StorageFailureAdvice.подзаголовок(возврат)),
                     systemImage: "externaldrive.badge.exclamationmark")

            if let предупреждение = StorageFailureAdvice.предупреждение(возврат) {
                TGBanner(tone: .alarm, title: "Переустановка удалит дневник",
                         subtitle: .готовая(предупреждение),
                         systemImage: "exclamationmark.triangle.fill")
            }

            TGCard {
                Text("Что попробовать").textStyle(AppFont.cardTitle)
                ForEach(StorageFailureAdvice.шаги(возврат), id: \.self) { step in
                    HStack(alignment: .top, spacing: Token.Space.s8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Token.Ink.secondary)
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
                Text(журналЗапуска)
                    .textStyle(AppFont.numeric(12, weight: .regular))
                    .wraps()
                TGExplainer(text: "Здесь только этапы запуска — ничего о собаке. Эти строки помогают понять причину.")
            }

            TGButton(title: "Написать в поддержку", variant: .secondary,
                     size: .medium, systemImage: "envelope") {
                // Тему письма человек ВИДИТ в окне почты, прежде чем
                // отправить. Русская строка здесь — то же самое, что
                // русская подпись на кнопке, только замечают её позже.
                //
                // Переводом мы платим тем, что в поддержку темы придут
                // на трёх языках. Это не потеря, а сигнал: по теме сразу
                // видно, на каком языке человеку отвечать.
                guard let url = Contacts.mail(Contacts.support,
                                              subject: String(localized: "Дневник не открылся")) else { return }
                openURL(url) { открылось in
                    guard !открылось else { return }
                    UIPasteboard.general.string =
                        "\(Contacts.support)\n\n\(StartupLog.read())"
                    копияАдреса = Contacts.support
                    Haptics.warning()
                }
            }
            if let копияАдреса {
                TGBanner(tone: .alarm, title: "Почта на телефоне не настроена",
                         // `.готовая` тут и раньше стояла — а строка под ней
                         // была сырым русским литералом и в каталог
                         // не попадала ни разу. Маркер обещает «текст уже
                         // собран и переведён», и под ним это проверять
                         // перестают: пропуск с обоснованием читается
                         // как решение.
                         //
                         // Экран отказа — та поверхность, которую француз
                         // видит ИМЕННО когда у него что-то сломалось.
                         subtitle: .готовая(String(localized: "Адрес и строки запуска скопированы: \(копияАдреса). Напиши с другого устройства.")),
                         systemImage: "envelope.badge.shield.half.filled")
            }
        }
    }

    // `steps` был КОНСТАНТОЙ из трёх пунктов, и третий звал
    // переустановить, обещая возврат «из iCloud или из сохранённого
    // файла». Переустановка сносит контейнер App Group, и у человека
    // без iCloud совет уничтожал то, что баннер над ним называл целым.
    //
    // Правило переехало в `StorageFailureAdvice` — чтобы его можно было
    // спросить из теста. Вью текстов больше не держит.
}
