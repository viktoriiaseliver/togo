import SwiftUI
import SwiftData
import StoreKit

/// Настройки. Всё, что Apple ожидает увидеть в приложении с подпиской
/// и с медицинской частью, лежит здесь одним списком.
struct SettingsScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionStore.self) private var store
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
            шапка
            subscriptionSection
            appearanceSection
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
        .navigationTitle("Настройки")
        // Шапка «Кино» НАД `navigationTitle`, а не вместо него.
        //
        // Заголовок нужен системе и после того, как его перестали
        // показывать: по нему подписана кнопка «назад» на дочерних
        // экранах и по нему же экран называет себя VoiceOver.
        // Сними `navigationTitle` — и дети получат безымянную стрелку.
        //
        // Было `.posterHeader(…)` — индиговая полоса плаката. Снята
        // решением Виктории 22.10.2026: «Кино» ЗАМЕНЯЕТ Graphite,
        // а не ложится третьим набором.
        .cinemaScreen(экран: .sub("settings"))
        // Панель вкладок на настройках не нужна и мешает.
        //
        // Настройки — не вкладка, а место, куда ушли с вкладки. Пока
        // панель видна, у экрана два выхода: «назад» возвращает туда,
        // откуда пришёл, а вкладка молча бросает начатое и уводит
        // в другое место. Эвристика №3, свобода и контроль: путь назад
        // должен быть один и понятный, а не два с разным смыслом.
        .toolbar(.hidden, for: .tabBar)
        .usageScreen(.settings)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallScreen() }
        }
    }

    // MARK: Шапка

    /// Крупный заголовок едет ПЕРВОЙ СТРОКОЙ СПИСКА, а не закреплён
    /// сверху, — и это снято с прототипа, а не выбрано на вкус.
    /// В `Togo-RU.dc.html` шапка страницы лежит внутри прокручиваемого
    /// контейнера, а фотография — отдельным слоем под ним
    /// (`position:absolute;top:0;height:360px`). То есть заголовок
    /// уезжает, фото остаётся.
    ///
    /// Закреплённая шапка здесь была бы хуже не видом, а поведением:
    /// под прозрачной шапкой проезжали бы строки списка, и название
    /// экрана читалось бы поверх чужого текста.
    private var шапка: some View {
        Section {
            // Строка надписи — ТОТ ЖЕ ключ, что стоял подзаголовком
            // плаката: «Язык, уведомления, перенос». Прописными её
            // делает `.textCase(.uppercase)` в самой шапке, а не другой
            // литерал. Строчная копия была бы НОВЫМ ключом каталога
            // (замер 23.10: у прежнего есть ru/en/fr/uk, у строчного
            // нет ничего), то есть переводом с нуля на пяти языках —
            // и работой чужой сессии, которая каталог сейчас вычитывает.
            CinemaHeader("Настройки",
                         надпись: "Язык, уведомления, перенос",
                         экран: .sub("settings"),
                         отступы: false)
        }
        // ПОЛЕ У ШАПКИ — ОТ СПИСКА, А НЕ НОЛЬ (правка 25.10.2026,
        // ДОКАЗАНА КАДРОМ на «Языке»).
        //
        // Здесь стояло `.listRowInsets(EdgeInsets())` — ноль со всех
        // сторон — и вместе с `отступы: false` давало шапке ноль плюс
        // ноль. Замер левого края краски, три кадра одного экрана:
        //
        // ```
        //                витрина-279   дефект   после починки   строки
        // надпись           x=106       x=56        x=100         x=99
        // заголовок         x=105       x=52        x= 99         x=99
        // ```
        //
        // Шапка стояла на 16 pt ЛЕВЕЕ своих же карточек. Это следствие
        // починки того же дня (`a33689d`): утром шапка была на 18 pt
        // ПРАВЕЕ карточек, и ей сняли её собственные 18 pt — а у карточек
        // поле не 18, а 33 (системное поле `.insetGrouped` плюс поле
        // ячейки), и ноль оказался перекоррекцией ровно на разницу.
        //
        // Обнуление снято ЦЕЛИКОМ, а не заменено числом: поле теперь
        // то же, что у строк, ПО ПОСТРОЕНИЮ. Магическое 33 разошлось бы
        // с системным при первой смене стиля списка — и молча.
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
                        // **Слово, а не только крутилка.** Правило
                        // дизайна круга 5, п. 1: выключенный орган
                        // допустим, только если рядом сказано, чего
                        // не хватает, — а при занятости не хватает
                        // времени, и это тоже надо сказать. Крутилку
                        // озвучка не читает вовсе.
                        //
                        // Ключ тот же, что на пейволле (`:293`):
                        // два входа в одно действие — одно слово,
                        // и новой строки в каталог не заводится.
                        Text(store.isRestoring ? "Спрашиваю магазин…" : "Восстановить покупки")
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
    /// модели не уезжают в iCloud вовсе.
    ///
    /// **Число здесь не стоит нарочно.** Прежде было «одиннадцать моделей
    /// из шестнадцати» — замер 23.09.2026, который к 14.10 устарел дважды:
    /// моделей стало 21, а не заведено было 83 поля, включая пять типов
    /// медслоя целиком. Число в комментарии проверить нечем, и оно
    /// стареет молча; живое говорит `make cloudkit-check`.
    ///
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
            // Единственный путь, которым видно уведомления.
            //
            // Кадром они не проверяются: экрана у них нет, их рисует
            // система. Без этой кнопки «запланировано» и «не
            // запланировано» дают один зелёный — чтобы проверить, что
            // что-то невидимо, нужен путь, который смотрит мимо показа.
            // Заведено вместе с подключением `NotificationPriming`,
            // а не после: иначе приёмка правила невозможна
            // по устройству.
            Button("Отладка · что запланировано в уведомлениях") {
                Task { warmupResult = await NotificationCenterService.отладочныйСписок() }
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
        case .cancelled:
            // Человек сам закрыл окно входа в App Store. Красная плашка
            // «не получилось» сказала бы ему о поломке там, где он принял
            // решение; окно, которое ушло, — уже ответ. Так же молчит
            // покупка на `.userCancelled`.
            EmptyView()
        case .failed:
            TGBanner(tone: .alarm, title: "Не получилось",
                     subtitle: store.lastError.map { .готовая($0) },
                     systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: Как выглядит

    /// Единственный вход в «Фон приложения».
    ///
    /// Строка стоит второй, сразу под подпиской, — так её ставит хендофф
    /// дизайна. Отдельной секцией, а не внутри «о приложении»: фон
    /// меняют, чтобы посмотреть, а не чтобы прочитать про версию.
    ///
    /// **Без этой строки `BackgroundStore` — механизм без входа.** Он
    /// компилируется, покрыт тестами и недостижим: ни одного другого
    /// пути в `BackgroundScreen` в приложении нет, и компилятор про это
    /// молчит. Сторож на вход — `BackgroundStoreTests.входСНастроекЕсть`.
    private var appearanceSection: some View {
        Section {
            NavigationLink {
                BackgroundScreen()
            } label: {
                // **Шевронов на строке было ДВА**, и видно это стало
                // только на кадре 23.10.2026: свой рисует `TGListRow`
                // (у него `accessory` по умолчанию `.chevron`), второй
                // добавляет сам `NavigationLink`. Прогон такого
                // не ловит по устройству — оба элемента законны
                // по отдельности. Убран наш: системный ставит ссылка,
                // и он же пропадёт, если строка перестанет быть ссылкой.
                TGListRow(title: "Фон приложения",
                          value: фонПодпись,
                          systemImage: "photo.on.rectangle.angled",
                          accessory: .none)
            }
        } header: {
            Text("как выглядит")
        }
    }

    /// Что стоит сейчас — словами, а не «настроено».
    private var фонПодпись: LocalizedStringKey {
        switch BackgroundStore.shared.choice.mode {
        case .auto: "как задумано"
        case .single: "одно фото для всех"
        case .random: "5 фото вперемешку"
        }
    }

    // MARK: Уведомления

    private var notificationsSection: some View {
        @Bindable var settings = settings
        return Section {
            NavigationLink {
                NotificationSettingsScreen()
            } label: {
                // «Утренняя» убрано: час выбирается от 5 до 21, и строка
                // противоречила бы собственному значению у всякого,
                // кто поставил сводку на вечер.
                LabeledContent("Сводка по уходу", value: Fmt.clock(minuteOfDay: settings.briefHour * 60))
            }
            LabeledContent("Тихие часы") {
                Text("\(Fmt.clock(minuteOfDay: settings.quietHoursStart * 60)) — \(Fmt.clock(minuteOfDay: settings.quietHoursEnd * 60))")
            }
            Toggle("Отклик при записи", isOn: $settings.haptics)
            NavigationLink("Язык") { LanguageScreen() }
        } header: {
            Text("что прерывает")
        } footer: {
            Text("Прерывают только доза по часам, окно натощак и лестница эскалации. Всё остальное придёт одним сообщением в выбранный час.")
        }
    }

    // MARK: Собака

    /// Показываем только то, что можно показать.
    ///
    /// **Ворота Pro считали безымянные записи наравне с собаками.**
    /// `dogs.isEmpty || store.isPro` при восьми фантомах даёт `false`,
    /// и человек без подписки видел «Добавить вторую собаку» с пейволлом
    /// вместо «Добавить собаку» — то есть завести ПЕРВУЮ настоящую
    /// собаку ему предлагали за деньги. Счётчик в заголовке врал
    /// по той же причине.
    private var показываемые: [Dog] { dogs.shownToPerson }

    private var dogSection: some View {
        Section {
            ForEach(показываемые) { dog in
                NavigationLink {
                    ProfileScreen(dog: dog)
                } label: {
                    LabeledContent(dog.displayName, value: Fmt.weight(dog.weightKg))
                }
                // Крючок для сторожа «пустые записи заведены и не видны
                // ни одна» (`TogoUITests/ПустыеСобаки`). До 25.10.2026
                // он считал строки **по подписи веса** — искал «0,0»,
                // потому что `Fmt.weight(0)` печатал «0,0 г», и это было
                // единственное, чем пустая строка отличалась от других.
                //
                // Прокси. Чини форматтер — и сторож зеленеет навсегда,
                // перестав видеть предмет: строк с «0,0» не будет
                // независимо от того, показываются пустые записи
                // или нет. Ось переставлена на САМУ СТРОКУ, и крючок
                // заведён здесь же, одним коммитом с починкой, чтобы
                // окна «зелен по прокси» не существовало.
                .accessibilityIdentifier("настройки-строка-собаки")
            }
            // Фильтр показа применяет сама фабрика `secondDog(among:)` —
            // не повторяем его здесь: `dogs.count` и
            // `dogs.shownToPerson.count` одного типа и разного смысла,
            // и промах между ними компилируется.
            if ProGate.isOpen(.secondDog(among: dogs), isPro: store.isPro) {
                NavigationLink("Добавить собаку") { DogEditorScreen() }
            } else {
                Button("Добавить вторую собаку") { showPaywall = true }
            }
        } header: {
            Text(показываемые.count > 1 ? "собаки" : "собака")
        } footer: {
            Text(показываемые.isEmpty
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

    /// Одна дверь вместо четырёх — как на эталоне `47-screens`.
    ///
    /// Здесь стояли четыре `NavigationLink` подряд: политика, условия,
    /// дисклеймер, открытый код. Четыре строки правового среди двух
    /// десятков строк настроек, и **смотрит сюда App Review**: он ищет
    /// политику и условия глазами по списку. Теперь они за одним словом
    /// «Правила», а сам раздел — `LegalScreen` в `LegalScreens.swift`.
    ///
    /// Двери не исчезли и не переименованы: `PrivacyPolicyScreen`,
    /// `TermsScreen`, `MedicalDisclaimerScreen`, `AcknowledgementsScreen`
    /// открываются теми же типами, на шаг глубже. Ссылки из текстов
    /// («Настройки → Данные и приватность») этой правкой не задеты —
    /// они ведут в `dataSection`, а не сюда.
    private var legalSection: some View {
        Section {
            NavigationLink("Правила") { LegalScreen() }
        } header: {
            Text("правовое")
        }
    }

    // MARK: О приложении

    private var aboutSection: some View {
        Section {
            NavigationLink("Как это работает") { HowItWorksScreen() }
            NavigationLink("Метка у двери") { DoorTagScreen() }
            // Вход к виджету и живой активности, заведён 28.10.2026.
            // До него человек из приложения не узнавал о них ничего:
            // виджет показывала только отладочная галерея под
            // `#if DEBUG` двумя разделами ниже. Строки «Вне приложения»,
            // «Виджеты и блокировка», «Live Activity и Dynamic Island»
            // лежали в каталоге переведёнными на четыре языка и
            // не вызывались из Swift ни разу.
            NavigationLink("Вне приложения") { ВнеПриложенияScreen() }
            Button("Пройти онбординг заново") { replayOnboarding() }
            // Вторым в паре и сразу под соседом: две кнопки про одно
            // слово «онбординг» делают разное, и если их развести
            // по экрану, человек прочтёт только ту, до которой дошёл.
            //
            // Сосед выше — ПЕРЕЧИТАТЬ: собака уже есть, и шаги, которые
            // её заводят, подменяются справкой, иначе получилась бы
            // вторая. Отсюда и односложность сообщения: он даёт один
            // экран из шести.
            //
            // Эта — ПОСМОТРЕТЬ, что видит новый человек: шесть
            // настоящих шагов подряд и ни одной записи в базу. Подпись
            // снизу не украшение: без неё обе строки отличаются
            // глаголом, а глагол здесь — единственное, что несёт смысл.
            //
            // Не под `#if DEBUG` по решению 14.10, и довод тот же, что
            // мы весь день ловим у других: сверять макет Виктория будет
            // на сборке TestFlight, а она Release — кнопка в отладке
            // была бы механизмом без входа ровно для того человека,
            // ради которого сделана.
            Button {
                appState.просмотрОнбординга = true
            } label: {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Посмотреть онбординг как новый")
                    // **Число шагов НЕ названо нарочно, и это замер
                    // 23.10.2026.** Здесь стояло «все шесть шагов» —
                    // и стало ложью в день, когда редизайн свёл онбординг
                    // к четырём (`OnboardingFlow.Step`: welcome · dog ·
                    // mode · notifications).
                    //
                    // > **Счёт в тексте — утверждение о коде, которое
                    // > стареет молча**, и здесь оно старело на виду
                    // > у человека: он читал «шесть», видел четыре
                    // > и получал повод не доверять остальному.
                    //
                    // Считать уезжающие числа мы уже перестали в двух
                    // местах по той же причине (языки на экране «Язык»,
                    // порог сюит в своде). Полнота тут и была смыслом —
                    // «не кусок, а всё подряд», — а она от числа
                    // не зависит.
                    Text("весь онбординг подряд; ничего не записывается")
                        .textStyle(AppFont.caption)
                }
            }
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
            // Единственное место, где строки виджета можно УВИДЕТЬ:
            // сам виджет рисует SpringBoard, и кадром его не снять.
            NavigationLink("Виджет") { WidgetGallery() }
            // Итог прогулки со срывом: тесты считали срывы верно,
            // а вид не строился нигде, кроме живой прогулки — до него
            // надо было выйти с собакой и вернуться.
            NavigationLink("Итог прогулки") { WalkSummaryGallery() }
            // Восемь состояний «Просится». Чтобы увидеть «отметок мочи
            // нет», надо было восемнадцать дней не вести дневник;
            // чтобы «мало данных» — удалить собаку и завести заново.
            NavigationLink("Просится") { VerdictGallery() }
            // Пять режимов плаката. На «Сегодня» виден ровно один —
            // тот, который сегодня; тревогу и час дозы надо было бы
            // устроить, чтобы увидеть. `PosterMode` при этом был
            // написан, покрыт тестами и не вызывался ниоткуда.
            NavigationLink("Плакат") { PosterGallery() }
            // Шесть трудных случаев медкнижки. Чтобы увидеть предел
            // обнаружения или «часы после дозы не записаны», надо было
            // загрузить архив с картой Стича — а экрана медкнижки
            // не существовало вовсе до 07.10.2026: обмен её возил,
            // архив хранил, смотреть было негде.
            NavigationLink("Медкнижка") { MedicalRecordGallery() }
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
                CinemaHeader("Уведомления",
                             надпись: "что прерывает",
                             экран: .sub("notifications"),
                             отступы: false)
            }
            // ПОЛЕ У ШАПКИ — ОТ СПИСКА, А НЕ НОЛЬ (правка 25.10.2026,
            // ДОКАЗАНА КАДРОМ на «Языке»).
            //
            // Здесь стояло `.listRowInsets(EdgeInsets())` — ноль со всех
            // сторон — и вместе с `отступы: false` давало шапке ноль плюс
            // ноль. Замер левого края краски, три кадра одного экрана:
            //
            // ```
            //                        витрина-279   дефект   после починки   строки
            // надпись               x=106       x=56            x=100             x=99
            // заголовок             x=105       x=52            x= 99             x=99
            // ```
            //
            // Шапка стояла на 16 pt ЛЕВЕЕ своих же карточек. Это следствие
            // починки того же дня (`a33689d`): утром шапка была на 18 pt
            // ПРАВЕЕ карточек, и ей сняли её собственные 18 pt — а у карточек
            // поле не 18, а 33 (системное поле `.insetGrouped` плюс поле
            // ячейки), и ноль оказался перекоррекцией ровно на разницу.
            //
            // Обнуление снято ЦЕЛИКОМ, а не заменено числом: поле теперь
            // то же, что у строк, ПО ПОСТРОЕНИЮ. Магическое 33 разошлось бы
            // с системным при первой смене стиля списка — и молча.
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // # Выбор ЧАСТИ ДНЯ — отзыв 28.10.2026
            //
            // Владелица, дословно: «Почему уход днём? Хочу выбирать
            // часть дня сама». Замер показал, что выбор был, и был
            // неполным:
            //
            // ```
            // Picker("Час сводки")  ForEach(5...12)   пять утра — полдень
            // заголовок секции      «утренняя сводка»
            // ```
            //
            // То есть поставить сводку на день или на вечер было нельзя
            // ни одним путём, а подпись называла её утренней при любом
            // выборе. Часть дня теперь выбирается первой, а час — внутри
            // неё: «когда» человек держит в голове частью дня, а не
            // числом.
            //
            // Второе поле в модели НЕ заводится: часть дня выводится
            // из часа (`ЧастьДня.по(часу:)`). Две величины об одном
            // разошлись бы молча — у нас это записано про любые две
            // копии числа.
            //
            // Повтор части дня — бездействие нарочно: человек, стоящий
            // на 10:00 и нажавший «утром», ждёт, что ничего не изменится,
            // а не что час уедет на умолчание 08:00.
            Section {
                Picker("Когда напоминать", selection: Binding(
                    get: { ЧастьДня.по(часу: settings.briefHour) },
                    set: { часть in
                        guard !часть.часы.contains(settings.briefHour) else { return }
                        settings.briefHour = часть.часПоУмолчанию
                    }
                )) {
                    ForEach(ЧастьДня.allCases) { часть in
                        Text(.готовая(часть.title)).tag(часть)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Точный час", selection: $settings.briefHour) {
                    ForEach(Array(ЧастьДня.по(часу: settings.briefHour).часы), id: \.self) { hour in
                        Text(Fmt.clock(minuteOfDay: hour * 60)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                // Пересборка висит ЗДЕСЬ, а не в сеттере части дня:
                // часть дня меняет именно `briefHour`, то есть этот
                // `onChange` срабатывает и на неё. Два места, зовущие
                // одну пересборку, разошлись бы — одно из них забыли бы.
                .onChange(of: settings.briefHour) { _, _ in
                    Task { await ReminderScheduler.scheduleBrief(dog: appState.activeDog(from: dogs), settings: settings) }
                }
            } header: {
                Text("сводка по уходу")
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
                // С 29.10.2026 тихие часы сдвигают сводку — значит
                // правка границы обязана её переставить сейчас, а не
                // при следующем открытии. «Можно кормить» переставит
                // ближайшая пересборка (возврат в приложение, сохранение).
                .onChange(of: settings.quietHoursEnd) { _, _ in
                    Task { await ReminderScheduler.scheduleBrief(dog: appState.activeDog(from: dogs), settings: settings) }
                }
                .onChange(of: settings.quietHoursStart) { _, _ in
                    Task { await ReminderScheduler.scheduleBrief(dog: appState.activeDog(from: dogs), settings: settings) }
                }
            } header: {
                Text("тихие часы")
            } footer: {
                // Тихие часы с 29.10.2026 читает и планировщик
                // уведомлений — футер обязан сказать, что именно они
                // глушат, а что нет: доза звонит всегда, и человек,
                // ставящий 23:00, должен знать это до ночи, а не в неё.
                // Разбор — голова `ReminderScheduler`.
                Text("В тихие часы приложение не спрашивает результат выхода — соберёт утром одной карточкой. Сводка и «Можно кормить» приходят в конце тихих часов. Доза приходит в свой час всегда.")
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
        // Стиль списка назван, а не оставлен «автоматическим»: решает
        // его иначе не тема, а контекст показа, и экран, собранный
        // одинаково, выглядел бы по-разному в зависимости от того,
        // откуда его открыли.
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .cinemaScreen(экран: .sub("notifications"))
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
