import Testing
import Foundation
import UIKit
@testable import Togo

/// Фон приложения: правило выбора фото и вход в него.
///
/// Проверяется не «считается ли», а три вещи, которых не видит
/// ни компилятор, ни прогон:
///
/// 1. **Хэш не зависит от процесса.** Подмени его на `hashValue` —
///    всё соберётся, все режимы будут работать, и виджет будет
///    показывать не то фото, что экран. Ловит это только замер
///    с ответом, известным заранее.
/// 2. **У механизма есть вход.** `BackgroundStore` без строки
///    в настройках компилируется и покрыт тестами, а человеку до него
///    не дойти.
/// 3. **Виджет зовёт чужое правило, а не своё.** Того уже обжигался
///    на том, что виджет считал окно «не кормить» собственной
///    арифметикой и молчал в двух случаях из трёх.
@Suite("Фон приложения")
struct BackgroundStoreTests {

    private static var корень: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func исходник(_ путь: String) throws -> String {
        try String(contentsOf: корень.appendingPathComponent(путь), encoding: .utf8)
    }

    private static let пятьФото = ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"]

    // MARK: Режимы

    @Test("Режимов ровно три, и по умолчанию стоит «как задумано»")
    func режимовТри() {
        // Первой — проверка, что проверять было что: на урезанном
        // перечислении остальное зеленело бы само.
        #expect(BackgroundMode.allCases.count == 3)
        #expect(Set(BackgroundMode.allCases.map(\.rawValue)) == ["auto", "single", "random"])
        #expect(BackgroundChoice().mode == .auto)
        #expect(BackgroundChoice.пусто.items.isEmpty)
    }

    @Test("«Как задумано» не подменяет фото даже тогда, когда фото есть")
    func автоНеПодменяет() {
        let выбор = BackgroundChoice(mode: .auto, items: Self.пятьФото)
        for ключ in ScreenKey.основные {
            #expect(выбор.photoName(for: ключ, seed: 7, fallback: "dog.jpg") == nil)
        }
        // Контроль в том же замере: фото в описи лежат, и другой режим
        // их находит. Без него «ноль» значил бы «список пуст».
        let тотЖеСписок = BackgroundChoice(mode: .single, items: Self.пятьФото)
        #expect(тотЖеСписок.photoName(for: .today, seed: 7, fallback: nil) == "a.jpg")
    }

    @Test("«Одно фото для всех» даёт первое из своих — на каждом экране")
    func одноДляВсех() {
        let выбор = BackgroundChoice(mode: .single, items: Self.пятьФото)
        for ключ in ScreenKey.основные {
            #expect(выбор.photoName(for: ключ, seed: 7, fallback: "dog.jpg") == "a.jpg")
        }
    }

    @Test("Без своих снимков «одно для всех» берёт фото собаки, а без него — ничего")
    func запасноеФото() {
        let пусто = BackgroundChoice(mode: .single, items: [])
        #expect(пусто.photoName(for: .today, seed: 7, fallback: "dog.jpg") == "dog.jpg")
        // Нет ни своих, ни собачьего — честное «фон берёт не отсюда»,
        // а не пустая картинка.
        #expect(пусто.photoName(for: .today, seed: 7, fallback: nil) == nil)
    }

    // MARK: Вперемешку

    @Test("Вперемешку: один экран держится, разные экраны расходятся")
    func вперемешку() {
        let выбор = BackgroundChoice(mode: .random, items: Self.пятьФото)
        let первый = выбор.photoName(for: .today, seed: 7, fallback: nil)
        #expect(первый == выбор.photoName(for: .today, seed: 7, fallback: nil))

        let разложено = ScreenKey.основные.compactMap {
            выбор.photoName(for: $0, seed: 7, fallback: nil)
        }
        #expect(разложено.count == ScreenKey.основные.count)
        // Не «все разные»: на пяти фото и шести экранах совпадения
        // неизбежны и ожидаемы. Проверяем, что раскладка не вырождена
        // в одно фото — именно это и значило бы сломанный хэш.
        #expect(Set(разложено).count > 1)
    }

    @Test("Новый запуск — новая раскладка")
    func затравкаМеняетРаскладку() {
        let выбор = BackgroundChoice(mode: .random, items: Self.пятьФото)
        let было = ScreenKey.основные.map { выбор.photoName(for: $0, seed: 7, fallback: nil) }
        let стало = ScreenKey.основные.map { выбор.photoName(for: $0, seed: 12345, fallback: nil) }
        #expect(было != стало)
    }

    /// **Главный сторож этого набора.**
    ///
    /// Числа посчитаны отдельно от кода — тем же правилом
    /// `h = h * 31 + байт` на Python 22.10.2026, — и в этом вся
    /// ценность: `hashValue` в Swift засевается случайно при каждом
    /// запуске процесса, поэтому подмена правила на него даст здесь
    /// другие числа **и будет давать разные числа при каждом прогоне**.
    /// Рассуждением это не ловится: оба варианта «работают».
    @Test("Хэш один и тот же в любом процессе — числа известны заранее")
    func хэшНеЗависитОтПроцесса() {
        let ожидаемое: [(String, Int)] = [
            ("today", 2), ("dog", 1), ("history", 3),
            ("health", 2), ("walk", 3), ("widget", 1),
        ]
        for (ключ, индекс) in ожидаемое {
            #expect(BackgroundChoice.индекс(ключ: ключ, seed: 7, из: 5) == индекс,
                    "\(ключ): раскладка разошлась с посчитанной руками")
        }
        // Затравки нет — берём семь, как прототип. Иначе «ещё
        // не спрашивали» и «семь» дали бы разные фото.
        #expect(BackgroundChoice.индекс(ключ: "today", seed: 0, из: 5)
                == BackgroundChoice.индекс(ключ: "today", seed: 7, из: 5))
        // Делить на ноль нечего, и падать тут нельзя: список фото
        // пустеет по кнопке «Убрать мои фото».
        #expect(BackgroundChoice.индекс(ключ: "today", seed: 7, из: 0) == 0)
    }

    @Test("Имя экрана идёт в хэш строкой, а не порядком — переименование видно")
    func ключЭкранаСтрокой() {
        #expect(ScreenKey.today.name == "today")
        #expect(ScreenKey.walk.name == "walk")
        #expect(ScreenKey.sub("family").name == "sub:family")
        // Виды плашки названы как ключи токена `backdrop.height`
        // в хендоффе: по ним слой показа берёт высоту.
        #expect(Set(BackdropKind.allCases.map(\.rawValue)) == ["today", "tab", "sub", "walk"])
        #expect(ScreenKey.today.kind == .today)
        #expect(ScreenKey.walk.kind == .walk)
        #expect(ScreenKey.widget.kind == .tab)
        #expect(ScreenKey.sub("family").kind == .sub)
    }

    // MARK: Пределы и снимки

    @Test("Больше пяти фото не кладём, и ключ хранения — из хендоффа")
    func пределИКлюч() {
        #expect(BackgroundChoice.maxPhotos == 5)
        #expect(BackgroundBridge.key == "togo-ios28-bg")
    }

    @Test("Снимок ужимается до тысячи точек и уезжает JPEG’ом")
    func снимокУжимается() throws {
        let большой = Self.картинка(width: 2400, height: 1600)
        let ужатое = try #require(ФонФото.ужать(большой))
        let картинка = try #require(UIImage(data: ужатое))
        #expect(max(картинка.size.width, картинка.size.height) <= ФонФото.maxSide)
        #expect(ужатое.count < большой.count)
        // JPEG начинается с FF D8 FF. PNG прошёл бы по размеру
        // и занял бы втрое больше.
        #expect(ужатое.prefix(3) == Data([0xFF, 0xD8, 0xFF]))

        // Контроль в том же замере: маленькое не растягиваем.
        let маленький = Self.картинка(width: 300, height: 200)
        let какЕсть = try #require(ФонФото.ужать(маленький))
        let тот = try #require(UIImage(data: какЕсть))
        #expect(max(тот.size.width, тот.size.height) <= 300)

        // И отрицательный контроль: не картинка — не снимок.
        #expect(ФонФото.ужать(Data("это не картинка".utf8)) == nil)
    }

    private static func картинка(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { контекст in
            // Шум, а не заливка: однотонный PNG сжимается до сотни байт,
            // и «ужатое меньше исходного» стало бы ложным.
            for x in stride(from: 0, to: width, by: 8) {
                for y in stride(from: 0, to: height, by: 8) {
                    UIColor(hue: CGFloat((Int(x + y) % 97)) / 97,
                            saturation: 1, brightness: 1, alpha: 1).setFill()
                    контекст.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
        return image.pngData() ?? Data()
    }

    // MARK: Вход

    /// Вопрос, которого не задаёт ни один сторож: **каким путём человек
    /// создаёт то, на чём механизм стоит.**
    @Test("Вход в «Фон приложения» есть, и он из настроек")
    func входСНастроекЕсть() throws {
        let настройки = try Self.исходник("Togo/Features/Settings/SettingsScreen.swift")
        #expect(настройки.contains("BackgroundScreen()"),
                "в настройках нет строки, ведущей в «Фон приложения» — механизм без входа")
        #expect(настройки.contains("Фон приложения"),
                "строка есть, а названия у неё нет — человек не поймёт, куда она ведёт")
        // Контроль в том же замере, на заведомо живой строке того же
        // файла: иначе «нет вхождений» значило бы «файл не прочитан».
        #expect(настройки.contains("Настройки"))

        let экран = try Self.исходник("Togo/Features/Settings/BackgroundScreen.swift")
        #expect(экран.contains("PhotosPicker"),
                "«Добавить фото» без системного выбора — вход без механизма")
    }

    @Test("Виджет берёт фото тем же правилом, а не своим")
    func виджетЗовётОбщееПравило() throws {
        let виджет = try Self.исходник("TogoWidgets/TodayWidget.swift")
        #expect(виджет.contains("BackgroundBridge.photo(for: .widget)"),
                "виджет не читает общий фон — обещание «виджет берёт то же фото» не выполняется")
        // Своей арифметики выбора у виджета быть не должно: одно
        // правило на приложение и расширение.
        #expect(!виджет.contains("photoName(for:"),
                "у виджета завелось собственное правило выбора — это второй источник правды")
        #expect(виджет.contains("Token.Surface.scrim"),
                "фото без затемнения съедает белые чернила на светлом снимке")
    }

    /// Красная линия проекта: снимки берутся только `PhotosPicker`’ом,
    /// и строк-описаний доступа в проекте нет.
    ///
    /// Проверяется **после** появления второго места со снимками:
    /// `PhotosPicker` работает в отдельном процессе и разрешения
    /// не требует, а ключ, добавленный «на всякий случай», превращает
    /// это в запрос доступа ко всей библиотеке — и в вопрос на ревью.
    @Test("Описаний доступа к библиотеке в проекте нет ни одного")
    func описанийДоступаНет() throws {
        for файл in ["Configuration/Togo-Info.plist", "Configuration/TogoWidgets-Info.plist"] {
            let текст = try Self.исходник(файл)
            #expect(!текст.contains("UsageDescription"),
                    "\(файл): заведено описание доступа — снимки берёт PhotosPicker, ему оно не нужно")
            // Контроль: файл прочитан и это правда plist.
            #expect(текст.contains("<key>"), "\(файл): прочитано пусто — замер не состоялся")
        }
    }
}
