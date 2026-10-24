import SwiftUI
import SwiftData
import PhotosUI

/// Вкладка «Собака».
///
/// Появилась после ревизии иерархии по HIG. Раньше всё про собаку —
/// питание, уход, документы, цикл, поездка, «если что-то случилось» —
/// висело под профилем, а профиль открывался из шторки «Ещё». То есть
/// запас корма лежал на четвёртом уровне вложенности, да ещё и внутри
/// модального экрана, из которого Apple прямо не советует строить
/// длинные цепочки.
///
/// Теперь это плоский список под своей вкладкой: до любого экрана
/// два тапа вместо четырёх.
///
/// **С 22.10.2026 «Семья» — первая строка этого списка** (решение
/// Виктории, `Дизайн/редизайн-ios28/README.md`, «Навигация (решено)»):
/// своей вкладки у неё больше нет. Первой, а не в середине: семья —
/// это про то, кто ещё ходит за собакой, и читается раньше запаса
/// корма.
///
/// **С 23.10.2026 экран переписан под тему «Кино».** Эталон — кадр
/// `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/09.png`, и мерено
/// по нему, а не по прозе пакета. Что изменилось против прежней редакции:
///
/// ```
/// плоская полоса `.posterHeader`   → фото 420 pt, надстрочник, кличка 36
/// опись собаки строкой с аватаром  → стеклянная карточка на фотографии
/// переключатель собак сверху       → под описью, как на кадре
/// «Семья» первым блоком            → после «Если что-то случилось»
/// заголовки секций внутри карточек → над карточками, как на кадре
/// «Если что-то случилось» строкой  → плашка `TGBanner`
/// ```
///
/// **Порядок «сперва тревога, потом семья» взят с кадра, и это смена
/// порядка, а не смена решения.** Решение называет «Семью» первой
/// строкой вкладки, и она ею остаётся: выше неё нет ни одной строки
/// списка — только шапка собаки и плашка на случай беды. Кадр `09`
/// показывает ровно это, и у плашки довод свой: искать телефон клиники
/// в панике некогда.
struct DogTab: View {
    /// Пришли по ссылке `togo://join/<token>` — открыть «Семью» сразу.
    /// Вкладки у неё нет, и довести человека до экрана обязан тот,
    /// кто поймал ссылку.
    @Binding var открытьСемью: Bool

    @Query private var skills: [ProcedureSkill]
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var trips: [Trip]
    @Query private var members: [FamilyMember]

    /// Настройки открываются из меню «…», а не шестерёнкой в шапке.
    @State private var открытьНастройки = false

    /// Снимок, выбранный кнопкой фотоаппарата на описи собаки.
    @State private var выбранныйСнимок: PhotosPickerItem?
    @State private var кладуСнимок = false

    @Environment(\.modelContext) private var context

    private var dog: Dog? { appState.activeDog(from: dogs) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if let dog {
                    герой(dog)
                    DogSwitcher(dogs: dogs, active: dog)
                    emergency(dog)
                    семьяБлок
                    everyday(dog)
                    documents(dog)
                    travel(dog)
                } else {
                    // Семья нужна и без собаки: человека могли позвать
                    // в чужой дневник, и собаку заводил не он.
                    семьяБлок
                    EmptyStateCard(
                        subject: .dog,
                        title: "Собаки пока нет",
                        message: "Заведи её — и приложению будет что считать.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
            .navigationTitle(dog.flatMap(\.nameIfAny) ?? String(localized: "Собака"))
            // Плоской полосы `.posterHeader` здесь больше нет: в «Кино»
            // под шапкой лежит фотография. Разбор — `ФотоШапка.swift`.
            .фотоШапкаЭкрана()
            .usageScreen(.profile)
            // Одна кнопка «…» вместо шестерёнки — решение 22.10.2026.
            // «Семья» есть и пунктом меню, и первой строкой списка:
            // хендофф называет оба места, и это не дубль по недосмотру.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HeaderMenu(настройки: { открытьНастройки = true },
                               семья: { открытьСемью = true })
                }
            }
            // Оба перехода — отсюда, а не из `Menu`: ссылка навигации
            // внутри меню срабатывает не всегда.
            .navigationDestination(isPresented: $открытьНастройки) {
                SettingsScreen()
            }
            .navigationDestination(isPresented: $открытьСемью) {
                FamilyScreen(встроенный: true)
            }
            .onChange(of: выбранныйСнимок) { _, новый in взятьСнимок(новый) }
        }
    }

    // MARK: Шапка с фотографией

    /// Блок `Hero` кадра `09`: фото собаки, порода и возраст
    /// надстрочником, кличка крупно, опись стеклом внизу.
    ///
    /// Поля экрана снимаются отрицательным отступом — ровно тем же
    /// приёмом, что у `DogSwitcher`: `TGScreen` кладёт содержимое
    /// в `screenPadding`, а фотография идёт во всю ширину.
    private func герой(_ dog: Dog) -> some View {
        ФотоШапка(фото: фотоЭкрана(dog),
                  высота: Token.Size.backdropTab,
                  надстрочник: надстрочник(dog),
                  заголовок: .значение(dog.displayName)) {
            опись(dog)
        }
        .padding(.horizontal, -Token.Spacing.screenPadding)
    }

    /// Фото вкладки спрашивается у `BackgroundStore`, как просит хендофф
    /// («экраны спрашивают `background(for: ScreenKey)`»).
    ///
    /// **`ScreenKey.dog` до 23.10.2026 не звал никто** — замер
    /// `git grep ScreenKey` по `*.swift` давал только экран настроек
    /// фона и сам домен. Ключ был объявлен, предпросмотр в настройках
    /// его рисовал, а живого экрана за ним не стояло.
    ///
    /// Запасное — фото собаки: в режиме «как задумано» (он же
    /// по умолчанию) хранилище отвечает `nil` нарочно, и без запасного
    /// шапка была бы пустым полотном у всех, кто своих снимков
    /// не добавлял.
    private func фотоЭкрана(_ dog: Dog) -> Data? {
        BackgroundStore.shared.background(for: .dog)?.data ?? dog.photo
    }

    /// «ШИППЕРКЕ · 3 ГОДА». Пусто, когда ни породы, ни возраста
    /// не записано: пустой надстрочник лучше, чем строчка из одной точки.
    ///
    /// Собирается здесь и уезжает `String`'ом — в нём порода, то есть
    /// данные человека. `.готовая(…)` для такого не годится: это
    /// обычный ключ каталога, и перевод он выполняет (разбор —
    /// `Подпись.swift`, живой отзыв `AEXYTDmy`).
    private func надстрочник(_ dog: Dog) -> String? {
        let части = [dog.breed, dog.ageDescription].compactMap { $0 }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    /// Опись собаки: кличка, порода, возраст, вес, чип.
    ///
    /// Стекло, а не `TGCard`: пакет называет блок `Hero` как «фото +
    /// стекло», и карточка на фотографии обязана фотографию пропускать.
    /// Путь отрисовки выбирает `TGGlass` — при выключенной прозрачности
    /// там сплошная поверхность, и это не наша забота.
    ///
    /// **Две цели касания, а не одна вложенная в другую.** Текст ведёт
    /// в профиль, фотоаппарат открывает выбор снимка; вложить кнопку
    /// в ярлык `NavigationLink` нельзя — срабатывает внешняя.
    private func опись(_ dog: Dog) -> some View {
        HStack(spacing: Token.Space.s12) {
            NavigationLink { ProfileScreen(dog: dog) } label: {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(dog.displayName).textStyle(AppFont.cardTitle)
                    Text(приметы(dog))
                        .textStyle(AppFont.caption)
                        .wraps()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            кнопкаСнимка
        }
        .padding(Token.Spacing.cardPadding)
        .стекло(.плавающее, радиус: Token.Radius.card)
    }

    /// «шипперке · 3 года · 8,4 кг · чип есть» — дословно с кадра `09`.
    ///
    /// Чип назван словом, а не номером: номер — это пятнадцать цифр,
    /// которые в опись не влезут, и читают его не здесь, а в документах.
    private func приметы(_ dog: Dog) -> String {
        let чип = dog.chipNumber == nil ? nil : String(localized: "чип есть")
        return [dog.breed, dog.ageDescription, Fmt.weight(dog.weightKg), чип]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Фотоаппарат на описи.
    ///
    /// **Это ВХОД, которого у `dog.photo` не было ни одного.** Замер
    /// 23.10.2026, `git grep "photo = "` по `Togo` и `TogoShared`
    /// при живом контроле (`breed = ` — девять мест, из них
    /// `Editors.swift:204` это редактор):
    ///
    /// ```
    /// OnboardingFlow.swift:299   dog.photo = photo   ← из DogDraft.photo,
    ///                            а DogDraft.photo НЕ ПИШЕТ НИКТО:
    ///                            объявлено на :281 и присваивания нет
    /// Backup.swift:563           восстановление из архива
    /// ```
    ///
    /// То есть поле читали три экрана (`DogChip`, `DogRow`, опись)
    /// и виджет, а положить в него снимок человек не мог **нигде**.
    /// Аватар всегда падал на букву, а фотография кадра `09` была
    /// недостижима по устройству.
    ///
    /// > **Механизм без входа не «почти работает» — он не работает.**
    /// > Ни компилятор, ни тест этого не видят: тесты заводят записи
    /// > сами. Проверяется вопросом, который не задаёт ни один сторож, —
    /// > каким путём человек создаёт то, на чём механизм стоит.
    ///
    /// Ужимает `ФонФото.ужать` — тот же, что у фона приложения: 1000 px
    /// по длинной стороне, JPEG 0,8. Своего числа здесь нет нарочно.
    ///
    /// **С 23.10.2026 вход не один.** Второй — пустой жетон в шапке
    /// «Сегодня» (`ЖетонСобаки`), решение дизайна, пункт 9. Разбор
    /// снимка у обоих общий — `ФотоСобаки.положить`, — и это не уборка,
    /// а требование: фото собаки стало подложкой по умолчанию, его
    /// читает виджет, и вход без ужатия убил бы расширение по памяти.
    private var кнопкаСнимка: some View {
        PhotosPicker(selection: $выбранныйСнимок, matching: .images,
                     photoLibrary: .shared()) {
            Image(systemName: "camera")
                .font(.system(size: Token.Size.iconLg, weight: .medium))
                .foregroundStyle(Token.Ink.primary)
                .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(кладуСнимок)
        .accessibilityLabel("Снимок собаки")
    }

    /// **Ярлык `PhotosPicker` — `@Sendable`-замыкание.** Внутрь него
    /// не уезжает ничего, кроме значков и токенов: `LocalizedStringKey`
    /// не `Sendable`, и возврат его из `MainActor`-метода роняет сборку
    /// схемы (замер 22.10.2026 на `BackgroundScreen.swift:116`).
    /// `-typecheck` из рецепта «собирается ли» этого не видит вовсе.
    private func взятьСнимок(_ item: PhotosPickerItem?) {
        guard let item, let dog else { return }
        кладуСнимок = true
        Task {
            defer { кладуСнимок = false; выбранныйСнимок = nil }
            // Разбор, ужатие, запись и журнал — в `ФотоСобаки.положить`:
            // у второго входа (жетон «Сегодня») тот же вызов, а не
            // такой же код.
            await ФотоСобаки.положить(item, в: dog, context: context,
                                      appState: appState, экран: .profile)
        }
    }

    // MARK: Секция

    /// Заголовок секции **над** карточкой, а не внутри неё.
    ///
    /// На кадре `09` заглавные «СЕМЬЯ» и «КАЖДЫЙ ДЕНЬ» стоят на полотне,
    /// а карточка начинается под ними. До 23.10 `TGSectionHeader` лежал
    /// внутри `TGCard` — то есть заголовок был частью карточки
    /// и прокручивался вместе с её фоном.
    ///
    /// Одной формой на все четыре секции, а не правкой в четырёх местах:
    /// пятая секция иначе появится по старому образцу, и расхождение
    /// увидят не раньше кадра.
    private func секция<Содержимое: View>(
        _ заголовок: LocalizedStringKey,
        подпись: LocalizedStringKey? = nil,
        @ViewBuilder содержимое: () -> Содержимое
    ) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: заголовок, subtitle: подпись)
            TGCard(spacing: 0) { содержимое() }
        }
    }

    // MARK: Семья — первая строка списка

    private var семьяБлок: some View {
        секция("семья") { семьяСтрока }
    }

    /// Первая строка списка. Ведёт на тот же экран, что и пункт меню,
    /// и тем же способом — через `открытьСемью`, а не вторым
    /// `NavigationLink`: два пути к одному экрану, собранные порознь,
    /// расходятся молча, и у Togo это записано трижды.
    private var семьяСтрока: some View {
        Button {
            UsageLog.note(.open, "family", on: .profile)
            открытьСемью = true
        } label: {
            TGListRow(title: "Семья и дежурство",
                      value: семьяПодпись,
                      systemImage: "person.2")
        }
        .buttonStyle(.plain)
    }

    /// Кто дежурит — чтобы строка говорила о состоянии, а не была
    /// просто дверью.
    ///
    /// Пусто, пока в семье никого, кроме хозяина: «1 человек» читается
    /// упрёком, а не фактом, — то же правило, по которому
    /// `procedureSummary` молчит на нуле попыток.
    ///
    /// Имя дежурного, а не число людей: число ничего не меняет в дне,
    /// а «дежурит Тео» отвечает на вопрос «кому писать, если что».
    ///
    /// **Хвост «роли · пригласить» взят с кадра `12`** и говорит, что
    /// за дверью, а не только кто дежурит. «Пригласить» дописывается
    /// только тому, у кого есть право звать: обещание, которого экран
    /// не исполнит, хуже отсутствия строки.
    private var семьяПодпись: LocalizedStringKey? {
        var части: [String] = []
        if let duty = members.first(where: \.isOnDuty) {
            части.append(String(localized: "дежурит \(duty.name)"))
        } else {
            let другие = members.filter { !$0.isMe }.count
            if другие > 0 { части.append(String(localized: "\(другие) кроме тебя")) }
        }
        части.append(String(localized: "роли"))
        if appState.can(.manageFamily) { части.append(String(localized: "пригласить")) }
        return .готовая(части.joined(separator: " · "))
    }

    /// Первым блоком и в терракоте: искать это в панике некогда.
    ///
    /// **Плашка, а не строка списка** — кадр `09` показывает здесь
    /// заливку во всю ширину с подписью в три пункта, и это единственный
    /// блок экрана, который должен останавливать взгляд.
    ///
    /// > ~~**Заливка у нас ОБРАТНАЯ кадру, и это названо, а не замазано.**
    /// > Перевернуть нечем: токена «тёмный текст на коралле»
    /// > в `tokens.json` нет вовсе.~~ **ЛОЖНО, и ложно было в момент
    /// > записи** (замер 24.10.2026). Токен есть и зовётся
    /// > `semantic.category.onIncident`; его собственное описание несёт
    /// > ровно это решение — «#111 там, где заливка светлая, белый там,
    /// > где тёмная», — и четыре числа замера рядом с ним. Живой читатель
    /// > у него был один, `CategoryBadge.swift:137`, поэтому грепом
    /// > по `overdueText` он и не находился: искали **чем красят подпись
    /// > тревоги**, а токен лежит в семье `Category`, не `Status`.
    ///
    /// Теперь плашка стоит `emphasis: .solid` — заливка `Category.incident`
    /// (терракот), чернила `Category.onIncident`. Замер 24.10.2026,
    /// композитом на том, что нарисовано (обе величины непрозрачны, alpha
    /// `FF`, так что композит равен самому цвету), порог 4,5 и 7
    /// в повышенном:
    ///
    /// ```
    ///            БЫЛО  коралл на бордо        СТАЛО  тёмное на коралле
    /// dark       #FF7A66 на #4D1F22   5,36    #111111 на #FF7A66   7,40
    /// light      #AE2219 на #F7D5CF   5,05    #FFFFFF на #AE2219   6,90
    /// darkHC     #FFA696 на #4D1F22   7,26    #111111 на #FFA696  10,02
    /// lightHC    #9B100E на #F7D5CF   6,21    #FFFFFF на #9B100E   8,49
    ///                          ↑ НЕ ХВАТАЛО при пороге 7
    /// ```
    ///
    /// **Это не только громкость: прежняя пара в светлом повышенном
    /// контрасте порога не брала** — 6,21 при 7. То есть правка под кадр
    /// закрыла заодно непрохождение, которого никто не искал, потому что
    /// у блока был вид решённого.
    private func emergency(_ dog: Dog) -> some View {
        NavigationLink { EmergencyScreen(dog: dog) } label: {
            TGBanner(tone: .alarm,
                     title: "Если что-то случилось",
                     subtitle: "телефоны · что мог съесть · справка врачу",
                     systemImage: "exclamationmark.triangle",
                     emphasis: .solid)
        }
        .buttonStyle(.plain)
    }

    // MARK: Каждый день

    private func everyday(_ dog: Dog) -> some View {
        секция("каждый день") {
                        TGLink(title: "Питание и режим", value: "\(dog.dailyGrams) г в день", systemImage: "fork.knife") { FeedingScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Уход", value: careSummary(dog).map { .готовая($0) }, systemImage: "scissors") { CareScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Вес", value: .готовая(Fmt.weight(dog.weightKg)), systemImage: "scalemass") { WeightScreen(dog: dog) }
            TGDivider()
            TGLink(title: "Перенос навыка", systemImage: "square.grid.3x3") { TransferMatrixScreen(dog: dog) }
            TGDivider()
            // Второй вход в «Процедуры», и он тут не для удобства.
            //
            // Единственный вход был с вкладки «Здоровье», а она есть,
            // только когда собака НА ЛЕЧЕНИИ (`RootView:46`). То есть
            // научить собаку спокойно давать лапу и залезать в переноску
            // можно было лишь тогда, когда лечение уже идёт, — а учат
            // этому заранее, ради того самого дня.
            //
            // Нашлось 28.09 кадром: тест записи попыток не смог дойти
            // до экрана у здоровой собаки. Прежний вход не трогаю —
            // с «Здоровья» он на месте.
            TGLink(title: "Подготовка к процедурам",
                   value: procedureSummary.map { .готовая($0) },
                   systemImage: "hand.raised") { ProcedurePrepScreen() }
            TGLink(title: "Занятия и шаги", value: trainingSummary(dog).map { .готовая($0) },
                   systemImage: "list.bullet") { TrainingLibraryScreen(dog: dog) }
            TGDivider()
            TGLink(title: dogs.count > 1 ? "Собаки" : "Завести ещё собаку",
                   value: dogs.count > 1 ? "\(dogs.count)" : nil,
                   systemImage: "pawprint") { DogsScreen() }
        }
        .buttonStyle(.plain)
    }

    /// «2 из 3 получается» — чтобы ссылка говорила о состоянии,
    /// а не была просто дверью. Пусто, пока ни одной попытки нет:
    /// «0 из 3» читается упрёком, а не фактом.
    private var procedureSummary: String? {
        guard !skills.isEmpty, skills.contains(where: { $0.attempts > 0 }) else { return nil }
        let получается = skills.filter { $0.status == .works }.count
        return String(localized: "\(получается) из \(skills.count) получается")
    }

    private func careSummary(_ dog: Dog) -> String? {
        let due = dog.careTasks.filter { $0.isDue() }.count
        return due > 0 ? String(localized: "\(due) сегодня") : nil
    }

    private func trainingSummary(_ dog: Dog) -> String? {
        let count = dog.trainingSessions.count
        return count == 0 ? nil : String(localized: "\(count) занятий")
    }

    // MARK: Документы и цикл

    private func documents(_ dog: Dog) -> some View {
        секция("на случай, когда спросят") {
                        TGLink(title: "Документы и контакты", value: dog.chipNumber == nil ? "не заполнены" : nil, systemImage: "doc.text.image") { DocumentsScreen(dog: dog) }
            if dog.tracksHeat {
                TGDivider()
                                TGLink(title: "Цикл", value: HeatCycle.forecast(dog.heats).expectedNext.map { .готовая(Fmt.shortDay($0)) }, systemImage: "calendar.badge.clock") { HeatScreen(dog: dog) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Поездки

    private func travel(_ dog: Dog) -> some View {
        let мои = trips.filter { $0.dog?.persistentModelID == dog.persistentModelID }
            .sorted { $0.startDate > $1.startDate }
        return секция("поездки",
                      подпись: мои.isEmpty ? "режим включится сам в день отъезда" : nil) {
            ForEach(мои) { trip in
                TGLink(title: .готовая(trip.destination),
                       value: trip.isActive() ? "идёт" : .готовая(Fmt.shortDay(trip.startDate)),
                       systemImage: trip.transport.symbol) { TripScreen(trip: trip, dog: dog) }
                TGDivider()
            }
                        TGLink(title: мои.isEmpty ? "Запланировать поездку" : "Ещё поездка", systemImage: "plus") { TripSetupScreen(dog: dog) }
        }
        .buttonStyle(.plain)
    }
}

// **`SettingsToolbarItem` снесён 23.10.2026.** Здесь стояла шестерёнка
// настроек, одна на все вкладки. Редизайн убрал её из шапки: настройки
// уехали в меню «…» (`HeaderMenu`), а само требование Apple — «настройки
// в предсказуемом месте» — исполняется там, первым пунктом меню.
//
// Тип пережил своё последнее место вызова на сутки по названной причине:
// `f4b5db9` снял шестерёнку с «Сегодня» и со вкладки собаки и записал
// в голове `RootView` «оставлен объявленным: его зовут `HealthScreen`
// и `HistoryScreen`, а это чужие пути». Причина была верной в тот день
// и умерла назавтра — `3e8eed6` снял обе оставшиеся шестерёнки, а запись
// про «чужие пути» никто не перечитал: **у наряда есть исполнитель,
// у устаревшей причины — нет.**
//
// Доказательство смерти (замер 23.10, вместе с контролем в той же
// команде): `SettingsToolbarItem` — три вхождения, и все три не вызовы
// (объявление плюс два доккомментария, которые про него и говорили);
// контроль `HeaderMenu(` — три живых вызова.

/// Заведённая поездка: что взять и когда что делать.
struct TripScreen: View {
    let trip: Trip
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        TGScreen {
            TGCard {
                HStack {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(trip.destination).textStyle(AppFont.cardTitle)
                        Text("\(Fmt.shortDay(trip.startDate)) — \(Fmt.shortDay(trip.endDate)) · \(Fmt.days(trip.dayCount()))")
                            .textStyle(AppFont.caption)
                    }
                    Spacer(minLength: Token.Space.s8)
                    if trip.isActive() {
                        Text("идёт").textStyle(AppFont.micro.color(Token.Status.doneText))
                    }
                }
                TGExplainer(text: .готовая(trip.transport.windowsExplainer))
            }

            PackingListCard(dog: dog, days: trip.dayCount())

            TGButton(title: "Убрать поездку", variant: .destructive,
                     size: .medium, systemImage: "trash") { isConfirmingDelete = true }
        }
        .navigationTitle(trip.destination)
        .cinemaScreen()
        .confirmationDialog("Убрать поездку?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                context.delete(trip)
                _ = context.persist(otherwise: {})
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи, сделанные в поездке, останутся в дневнике.")
        }
    }
}
