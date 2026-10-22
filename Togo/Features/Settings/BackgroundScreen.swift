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
            режимы
            снимки
            предпросмотр
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .navigationTitle("Фон приложения")
        .posterHeader("Фон приложения", subtitle: "чьё фото видно за экранами")
        .navigationBarTitleDisplayMode(.inline)
        .usageScreen(.settings)
        .onChange(of: picked) { _, item in взять(item) }
        // Единственный вход запасного фото: база с собакой живёт
        // в приложении, а виджету нужны байты в общей группе.
        .task { store.запомнитьФотоСобаки(appState.activeDog(from: dogs)?.photo) }
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
            Text("Фон — это фотография за экранами, а не тема. Светлую и тёмную переключают отдельно.")
        }
    }

    private func заголовок(_ mode: BackgroundMode) -> LocalizedStringKey {
        switch mode {
        case .auto: "Как задумано"
        case .single: "Одно фото для всех"
        case .random: "5 фото вперемешку"
        }
    }

    private func подпись(_ mode: BackgroundMode) -> LocalizedStringKey {
        switch mode {
        case .auto: "у каждого раздела своё"
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

    private var снимки: some View {
        Section {
            if store.сколькоМоих > 0 {
                полоскаСнимков
            }
            if store.естьМесто {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    TGListRow(title: "Добавить фото",
                              value: .готовая(String(localized: "\(store.сколькоМоих) из \(BackgroundChoice.maxPhotos)")),
                              systemImage: "photo.badge.plus",
                              accessory: .none,
                              tone: Token.Action.primary)
                }
                .buttonStyle(.plain)
                .disabled(кладу)
            } else {
                TGListRow(title: "Больше пяти не положить",
                          value: .готовая(String(localized: "\(store.сколькоМоих) из \(BackgroundChoice.maxPhotos)")),
                          systemImage: "photo.badge.plus",
                          accessory: .none,
                          tone: Token.Ink.secondary)
            }
            if store.сколькоМоих > 0 {
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

    private var подписьПодПредпросмотром: LocalizedStringKey {
        switch store.choice.mode {
        case .auto: "Каждый раздел берёт то фото, которое ему подобрали."
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

    static func ужать(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let сторона = max(image.size.width, image.size.height)
        guard сторона > maxSide else { return image.jpegData(compressionQuality: quality) ?? data }

        let масштаб = maxSide / сторона
        let размер = CGSize(width: image.size.width * масштаб,
                            height: image.size.height * масштаб)
        let renderer = UIGraphicsImageRenderer(size: размер)
        let ужатое = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: размер)) }
        return ужатое.jpegData(compressionQuality: quality)
    }
}
