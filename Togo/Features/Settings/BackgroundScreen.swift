import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Настройки → «Фон приложения». Три режима и свои снимки.
///
/// **Экран существует ради того, чтобы механизм имел вход.**
/// `BackgroundStore` без него был бы ровно тем, что мы ловим в Того
/// четвёртый месяц: правило написано, тестами покрыто, и человеку
/// до него не дойти. Поэтому здесь же, а не «потом», стоит предпросмотр:
/// выбор без видимого исхода — это тумблер, про который нельзя сказать,
/// сработал он или нет.
/// `@MainActor` поставлен руками, хотя у приложения он и так
/// по умолчанию: рецепт «собирается ли» из `CLAUDE.md` зовёт `swiftc`
/// **без** `-default-isolation MainActor`, и свойство `store`
/// в непомеченном типе читается там как неизолированное. То же правило,
/// что про расширение виджетов: изоляция по умолчанию — свойство
/// сборки, а не файла.
@MainActor
struct BackgroundScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceTransparency) private var снизитьПрозрачность
    @Environment(\.accessibilityReduceMotion) private var снизитьДвижение
    @Query private var dogs: [Dog]

    /// Хозяин фона один на приложение. Наблюдение за `@Observable`
    /// работает от чтения свойств в `body`, а не от способа получить
    /// объект, — поэтому окружение здесь не нужно и `TogoApp` трогать
    /// не приходится.
    private var store: BackgroundStore { .shared }

    @State private var picked: PhotosPickerItem?
    @State private var кладу = false

    var body: some View {
        List {
            шапка
            режимы
            снимки
            предпросмотр
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Фон приложения")
        // **Фон этого экрана — его же предмет.** До 23.10.2026 здесь
        // стояла индиговая полоса плаката, и человек, выбравший фото,
        // не видел его нигде: ни на этом экране, ни на соседних.
        // Теперь выбранное фото лежит под шапкой тут же — выбор получил
        // видимый исход на том самом экране, где он сделан.
        .cinemaScreen(экран: .sub("background"))
        .usageScreen(.settings)
        .onChange(of: picked) { _, item in взять(item) }
        // Единственный вход запасного фото: база с собакой живёт
        // в приложении, а виджету нужны байты в общей группе.
        .task { store.запомнитьФотоСобаки(appState.activeDog(from: dogs)?.photo) }
    }

    // MARK: Шапка

    private var шапка: some View {
        Section {
            CinemaHeader("Фон приложения",
                         надпись: "чьё фото видно за экранами",
                         экран: .sub("background"))
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Режимы

    private var режимы: some View {
        Section {
            ForEach(BackgroundMode.allCases, id: \.self) { mode in
                Button {
                    if снизитьДвижение {
                        store.выбрать(mode)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { store.выбрать(mode) }
                    }
                } label: {
                    TGListRow(title: заголовок(mode),
                              value: подпись(mode),
                              systemImage: значок(mode),
                              accessory: store.choice.mode == mode ? .checkmark : .none)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.choice.mode == mode ? .isSelected : [])
            }
        } header: {
            Text("как выбирается фото")
        } footer: {
            // **Вторая половина строки стала ложью 23.10.2026**, и
            // переписана она, а не выброшена целиком: первая —
            // единственное место, где человеку объясняют разницу между
            // фоном и темой, и путают их постоянно.
            //
            // Было: «Светлую и тёмную переключают отдельно». Решение
            // Виктории 23.10.2026 — «Кино. Одна тема»: `UIUserInterfaceStyle
            // = Dark` стоит в обоих plist (приложения и виджетов),
            // переключать больше нечего. Светлые значения токенов
            // остаются записью дизайнера и живут в превью — на телефон
            // они не попадают.
            Text("Фон — это фотография за экранами, а не тема. Тема в Togo одна — тёмная.")
        }
    }

    private func заголовок(_ mode: BackgroundMode) -> LocalizedStringKey {
        switch mode {
        case .auto: "Как задумано"
        case .single: "Одно фото для всех"
        case .random: "5 фото вперемешку"
        }
    }

    /// **Подпись `auto` переписана 23.10.2026: она обещала набор,
    /// которого не будет.**
    ///
    /// Было «у каждого раздела своё» — и это читалось как «дизайн
    /// подобрал фотографию каждому разделу». Ответ круга 2, пункт 1
    /// закрыл ожидание прямо: «Набор фото разделов мы не отдаём. Фото
    /// в прототипе взяты с Unsplash как заглушки… „Кино" строится
    /// на фото собаки пользователя». Цепочка теперь «своё фото →
    /// `Dog.photo` → чёрный», и первая её ступень в `auto`
    /// **недостижима по устройству**: первый же добавленный снимок
    /// переводит режим в `single` (`BackgroundStore.добавить`).
    /// Значит в `auto` остаются ровно две ступени из трёх, и подпись
    /// называет их.
    ///
    /// > Это не опечатка и не устаревание текста рядом с рабочим
    /// > механизмом: **механизм сменил смысл, а подпись осталась
    /// > от прежнего.** Человек выбирал режим по обещанию, которого
    /// > приложение не исполняет, — и «ничего не поменялось» выглядело
    /// > поломкой, а не ответом.
    ///
    /// Имя режима («Как задумано») при этом НЕ менялось: его называет
    /// README хендоффа, и круг 2 переименования не просил. Устарело
    /// объяснение, а не название.
    private func подпись(_ mode: BackgroundMode) -> LocalizedStringKey {
        switch mode {
        case .auto: "фото собаки, а без него чёрный"
        case .single: store.сколькоМоих > 0 ? "первое из твоих" : "фото собаки, пока своих нет"
        case .random: "у каждого экрана своё; меняется при запуске"
        }
    }

    private func значок(_ mode: BackgroundMode) -> String {
        switch mode {
        case .auto: "rectangle.on.rectangle"
        case .single: "photo"
        case .random: "shuffle"
        }
    }

    // MARK: Свои снимки

    /// **Ярлык `PhotosPicker` — `@Sendable`-замыкание**, и это замер,
    /// а не осторожность. Сборка схемы 22.10.2026 упала здесь:
    ///
    /// ```
    /// BackgroundScreen.swift:116:39: error: non-Sendable
    /// 'LocalizedStringKey'-typed result can not be returned from main
    /// actor-isolated static method 'готовая' to nonisolated context
    /// ```
    ///
    /// `LocalizedStringKey` не `Sendable`, а `.готовая` изолирован
    /// `MainActor` по умолчанию таргета. Поэтому внутрь замыкания
    /// уезжает только `String` — он `Sendable`, — а ключ каталога
    /// строится уже там, системным `init`, у которого изоляции нет.
    /// `.готовая` остаётся снаружи, где контекст `MainActor`.
    ///
    /// > **`-typecheck` из рецепта «собирается ли» этого НЕ ВИДИТ.**
    /// > Он зовётся без `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// > а ошибка возникает **именно из-за** этого умолчания: без него
    /// > `.готовая` неизолирована и законна. Рецепт ответил «чисто»
    /// > верно — на свой вопрос, и вопрос был не тот. Для всего, что
    /// > трогает изоляцию, честная проверка одна: **сборка схемы**.
    ///
    /// Счёт и оба признака считаются до замыкания ещё и затем, чтобы
    /// `store` в него не попадал: чтение `MainActor`-свойства оттуда
    /// даёт предупреждение, которое завтра станет ошибкой.
    private var снимки: some View {
        let счёт = String(localized: "\(store.сколькоМоих) из \(BackgroundChoice.maxPhotos)")
        let естьМои = store.сколькоМоих > 0
        let местоЕсть = store.естьМесто
        return Section {
            if естьМои {
                полоскаСнимков
            }
            if местоЕсть {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    TGListRow(title: "Добавить фото",
                              value: LocalizedStringKey(счёт),
                              systemImage: "photo.badge.plus",
                              accessory: .none,
                              tone: Token.Action.primary)
                }
                .buttonStyle(.plain)
                .disabled(кладу)
            } else {
                TGListRow(title: "Больше пяти не положить",
                          value: .готовая(счёт),
                          systemImage: "photo.badge.plus",
                          accessory: .none,
                          tone: Token.Ink.secondary)
            }
            if естьМои {
                Button(role: .destructive) {
                    store.убратьМои()
                    Haptics.warning()
                } label: {
                    TGListRow(title: "Убрать мои фото",
                              systemImage: "trash",
                              accessory: .none,
                              tone: Token.Status.overdueText)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("твои фотографии")
        } footer: {
            Text("Снимки лежат на телефоне и уезжают только в виджет — он берёт то же фото, что и экран. Длинная сторона ужимается до тысячи точек, чтобы не занимать место.")
        }
    }

    private var полоскаСнимков: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Token.Space.s8) {
                ForEach(store.мои) { фото in
                    плитка(фото)
                }
            }
            .padding(.vertical, Token.Space.s4)
        }
    }

    private func плитка(_ фото: BackgroundPhoto) -> some View {
        Group {
            if let image = UIImage(data: фото.data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Token.Surface.sunken
            }
        }
        .frame(width: Token.Size.capsule, height: Token.Size.capsule)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Предпросмотр

    /// Что человек увидит. Без этого выбор режима — слово без исхода:
    /// «вперемешку» и «как задумано» отличаются только тем, что
    /// нарисуется потом и в другом месте.
    private var предпросмотр: some View {
        Section {
            ForEach(ScreenKey.основные, id: \.self) { ключ in
                HStack(spacing: Token.Space.s12) {
                    окно(ключ)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(имяЭкрана(ключ)).textStyle(AppFont.body)
                        Text(исход(ключ)).textStyle(AppFont.caption).wraps()
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Token.Size.tapTarget)
            }
        } header: {
            Text("что получится")
        } footer: {
            Text(подписьПодПредпросмотром)
        }
    }

    /// **Строка про `auto` переписана вместе с подписью режима.**
    /// «Каждый раздел берёт то фото, которое ему подобрали» называло
    /// подбиравшего, которого нет: набора разделов не будет (круг 2,
    /// пункт 1). Тут же названо и то, что дизайн назвал нормой:
    /// «Чистая установка без фото собаки даёт чёрные вкладки — это
    /// нормально». Без этой половины пустой предпросмотр читается
    /// как «не загрузилось».
    private var подписьПодПредпросмотром: LocalizedStringKey {
        switch store.choice.mode {
        case .auto: store.background(for: .today) == nil
            ? "Фотографии собаки пока нет — экраны чёрные. Положи её в карточку собаки, и подложка появится везде."
            : "Под всеми разделами фото собаки из её карточки."
        case .single: store.сколькоМоих > 0
            ? "Везде первое из твоих. Чтобы поменять — убери фото и положи другое первым."
            : "Пока своих фотографий нет, везде будет фото собаки из её карточки."
        case .random: "Расклад держится до следующего запуска приложения, потом перемешается заново."
        }
    }

    private func окно(_ ключ: ScreenKey) -> some View {
        Group {
            if let фото = store.background(for: ключ), let image = UIImage(data: фото.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(стекло)
            } else {
                Token.Surface.sunken
            }
        }
        .frame(width: Token.Size.capsule, height: Token.Size.controlM)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Стеклянная полоса поверх фото — та самая панель показания
    /// в миниатюре.
    ///
    /// **Сниженная прозрачность убирает не только блюр.** Стекло
    /// с подложкой `surface-raised` — это сплошная плашка; материал
    /// под ней не рисуется вовсе, иначе «без блюра» осталось бы
    /// обещанием в настройках системы.
    private var стекло: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if снизитьПрозрачность {
                    Token.Surface.control
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .frame(height: Token.Space.s16)
        }
    }

    private func имяЭкрана(_ ключ: ScreenKey) -> LocalizedStringKey {
        switch ключ.name {
        case ScreenKey.today.name: "Сегодня"
        case ScreenKey.dog.name: "Вкладка собаки"
        case ScreenKey.history.name: "История"
        case ScreenKey.health.name: "Здоровье"
        case ScreenKey.walk.name: "На улице"
        case ScreenKey.widget.name: "Виджет"
        default: .готовая(ключ.name)
        }
    }

    /// Словами — что именно получит экран. Номер фото, а не «включено»:
    /// в режиме «вперемешку» вся суть в том, что номера разные.
    private func исход(_ ключ: ScreenKey) -> LocalizedStringKey {
        guard let фото = store.background(for: ключ) else {
            return "фото раздела"
        }
        if фото.name == BackgroundBridge.dogFallbackName {
            return "фото собаки"
        }
        guard let номер = store.choice.items.firstIndex(of: фото.name) else {
            return "твоё фото"
        }
        return .готовая(String(localized: "твоё фото № \(номер + 1)"))
    }

    // MARK: Что делает «Добавить фото»

    private func взять(_ item: PhotosPickerItem?) {
        guard let item else { return }
        кладу = true
        Task {
            defer { кладу = false; picked = nil }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let ужатое = ФонФото.ужать(raw)
            else {
                return appState.showFailure(String(localized: "Снимок не открылся · попробуй другой"))
            }
            guard store.добавить(ужатое) else {
                return appState.showFailure(String(localized: "Снимок не лёг · попробуй ещё раз"))
            }
            Haptics.success()
        }
    }
}

/// Снимок фона: ужать до тысячи точек по длинной стороне и сжать в JPEG.
///
/// Числа — из хендоффа дизайна (`Фон приложения`: «до 5, уменьшать
/// до 1000 px, JPEG 0.8»). Отдельно от `DocumentPhoto`, у которого
/// свои 1600 и 0.7: документ читают, фон рассматривают, и сводить это
/// в одно число значит потерять обе причины.
nonisolated enum ФонФото {
    static let maxSide: CGFloat = 1000
    static let quality: CGFloat = 0.8

    /// **Меряет и рисует в ПИКСЕЛЯХ, а не в точках.** Обе половины этого
    /// — починка, а не осторожность; замер 23.10.2026, прогон поймал:
    ///
    /// ```
    /// просили ужать до 1000   получили 3000   ровно ×3, масштаб экрана
    /// ```
    ///
    /// `UIImage.size` — **точки**, а `UIGraphicsImageRenderer(size:)` без
    /// формата рисует в масштабе устройства (на iPhone 3×). Прежняя
    /// редакция складывала обе ошибки в одну сторону: мерила точки,
    /// сравнивала их с пределом в пикселях и рендерила втрое крупнее
    /// запрошенного. Обещание «до 1000 точек» нарушалось втрое, а вес
    /// файла — примерно вдевятеро, и уезжал он в App Group, откуда
    /// его читает ещё и виджет.
    ///
    /// > **Ни компилятор, ни глаз этого не видят:** картинка выглядит
    /// > правильной, просто она в девять раз тяжелее. Поймало только
    /// > число в тесте.
    ///
    /// `format.scale = 1` делает пиксель выхода равным запрошенной
    /// единице, поэтому дальше вся арифметика — одна система координат.
    static func ужать(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        // Пиксели, а не точки: у снимка из `PhotosPicker` масштаб бывает
        // любым, и `size` о нём не говорит.
        let ширина = image.size.width * image.scale
        let высота = image.size.height * image.scale
        let сторона = max(ширина, высота)
        guard сторона > maxSide else {
            // Маленькое не растягиваем — но перекодируем в JPEG, иначе
            // PNG от `PhotosPicker` занял бы втрое больше при том же виде.
            return image.jpegData(compressionQuality: quality) ?? data
        }

        let масштаб = maxSide / сторона
        let размер = CGSize(width: ширина * масштаб, height: высота * масштаб)
        let формат = UIGraphicsImageRendererFormat.default()
        формат.scale = 1
        формат.opaque = true
        let renderer = UIGraphicsImageRenderer(size: размер, format: формат)
        let ужатое = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: размер)) }
        return ужатое.jpegData(compressionQuality: quality)
    }
}
