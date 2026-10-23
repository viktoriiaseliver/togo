import SwiftUI
import SwiftData
import PhotosUI

/// Единственный путь, которым снимок попадает в `Dog.photo`.
///
/// # Зачем отдельное место
///
/// Входов в поле теперь **два** — фотоаппарат на описи собаки
/// (`DogTab.кнопкаСнимка`, с 23.10.2026) и пустой жетон в шапке
/// «Сегодня» (`ЖетонСобаки`, решение дизайна того же дня, пункт 9
/// `Дизайн/редизайн-ios28/ОТВЕТЫ-круг-2.md`). У Togo записано трижды:
/// **два пути к одному результату, собранные порознь, расходятся
/// молча**. Здесь расхождение стоило бы дороже обычного.
///
/// # Чем именно дороже: ужатие — не косметика
///
/// Снимок уезжает не только на экран. Фото собаки с 23.10.2026 —
/// **подложка по умолчанию** (ответ дизайна, пункт 1: своё фото
/// раздела → `Dog.photo` → чёрный), то есть его читает и виджет,
/// а расширение ограничено по памяти жёстко: кадр 3000 px
/// разворачивается примерно в 36 МБ и убивает виджет целиком.
/// Поэтому оба входа обязаны звать `ФонФото.ужать` — 1000 px
/// по длинной стороне, JPEG 0,8, — и своего числа ни у одного
/// из них нет.
///
/// > **Второй вход, заведённый «так же, как первый», — это копия,
/// > а не тот же путь.** Тот же путь — это один вызов.
enum ФотоСобаки {

    /// Положить снимок в собаку. Возвращает, легло ли.
    ///
    /// `appState` необязателен: жетон рисуется и там, где состояния
    /// приложения в окружении может не быть (галерея компонентов,
    /// превью). Падать из-за отсутствия тоста — худшая из цен.
    @MainActor
    @discardableResult
    static func положить(_ item: PhotosPickerItem,
                         в dog: Dog,
                         context: ModelContext,
                         appState: AppState?,
                         экран: UsageLog.Screen) async -> Bool {
        guard let сырое = try? await item.loadTransferable(type: Data.self),
              let ужатое = ФонФото.ужать(сырое)
        else {
            appState?.showFailure(String(localized: "Снимок не открылся · попробуй другой"))
            return false
        }
        dog.photo = ужатое
        guard context.persist(otherwise: {}) else {
            Haptics.warning()
            UsageLog.note(.record, "dogPhoto", on: экран, outcome: .failed)
            return false
        }
        UsageLog.note(.record, "dogPhoto", on: экран, outcome: .done)
        Haptics.success()
        return true
    }
}

/// Аватар-жетон в шапке «Сегодня». **Пустой — открывает выбор фото.**
///
/// Дизайн, 23.10.2026, пункт 9 дословно: «`PhotosPicker` на вкладке
/// собаки — это и есть то место. Второй вход: тап по пустому
/// аватару-жетону в шапке „Сегодня“ открывает тот же `PhotosPicker`.
/// Онбординг не трогаем: там только кличка и фраза.»
///
/// # Почему только ПУСТОЙ
///
/// Так сказано в решении, и довод у него свой: жетон с фотографией —
/// это уже сведения, а не кнопка, и тап по нему человек ждёт как
/// переход, а не как замену снимка. Поменять фото можно там же, где
/// его кладут первым входом, — на вкладке собаки.
///
/// # Ярлык `PhotosPicker` — `@Sendable`-замыкание
///
/// Внутрь него уезжает **только `String`**: инициал считается
/// снаружи. `Dog` не `Sendable`, и захват модели в ярлык — это тот же
/// класс ошибки, что уронил сборку схемы 22.10.2026 на
/// `BackgroundScreen.swift:116`. Рецепт «собирается ли» из
/// `Togo/CLAUDE.md` такого **не видит по устройству**: он зовётся
/// без `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, и ошибки
/// при этом не возникает вовсе. Честная проверка здесь одна —
/// сборка схемы.
struct ЖетонСобаки: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    /// Необязателен нарочно — см. `ФотоСобаки.положить`.
    @Environment(AppState.self) private var appState: AppState?

    @State private var выбранный: PhotosPickerItem?
    @State private var кладу = false

    var body: some View {
        if let dog, dog.photo == nil {
            жетонСВыбором(dog.initial)
                .onChange(of: выбранный) { _, новый in взять(новый, для: dog) }
        } else {
            DogAvatar(dog: dog)
        }
    }

    /// Ярлык берёт **инициал строкой**, а не собаку: см. голову типа.
    private func жетонСВыбором(_ инициал: String) -> some View {
        PhotosPicker(selection: $выбранный, matching: .images,
                     photoLibrary: .shared()) {
            TGAvatar(initial: инициал,
                     size: Token.Size.avatarMd,
                     tint: Token.Action.doneQuiet)
        }
        .buttonStyle(.plain)
        .disabled(кладу)
        // `TGAvatar` прячет себя от озвучки (`accessibilityHidden`),
        // поэтому элемент собирается здесь явно: без этого у жетона
        // не было бы ни имени, ни признака кнопки, и слепой человек
        // второго входа не нашёл бы вовсе.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Снимок собаки")
        .accessibilityAddTraits(.isButton)
    }

    /// Своего разбора снимка здесь нет — он один на оба входа.
    private func взять(_ item: PhotosPickerItem?, для dog: Dog) {
        guard let item else { return }
        кладу = true
        Task {
            defer { кладу = false; выбранный = nil }
            await ФотоСобаки.положить(item, в: dog, context: context,
                                      appState: appState, экран: .today)
        }
    }
}
