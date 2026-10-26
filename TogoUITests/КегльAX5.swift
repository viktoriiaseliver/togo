import XCTest

/// Восемь экранов на **AX5** (`UICTContentSizeCategoryAccessibilityXXXL`),
/// и у каждого — свой кадр на обычном кегле **в том же заходе**.
///
/// # Почему набор заведён 25.10.2026, когда наборов с «крупным кеглем»
/// уже четыре
///
/// Все четыре снимали через `ImageRenderer` с
/// `.environment(\.dynamicTypeSize, …)`, и **кегль там не менялся
/// вовсе**: `TextStyleToken.font` (`Typography.swift:44`) считает размер
/// через `UIFontMetrics(forTextStyle:).scaledValue(for:)`, а тот читает
/// настройку **процесса** — не окружение SwiftUI и не
/// `UITraitCollection.current`. Пары кадров совпали побайтово.
///
/// Способ, которым снимает этот набор, измерен, а не взят на веру
/// (`ЗондКрупногоКегля`, три запуска в одном прогоне):
///
/// ```
/// A обычный      высота подписи 24,00 pt   md5 84e4bd50…
/// B AX5          высота подписи 62,33 pt   md5 01b48d96…   ← различие есть
/// C контроль     высота подписи 24,00 pt   md5 84e4bd50…   ← совпал с A побайтово
/// окно во всех трёх 402×874 — контроль на «померил ли я вообще то»
/// ```
///
/// Контроль `C` здесь не украшение: кадр содержит часы и живые данные,
/// и без него «хеши разошлись» не отличить от «кегль сменился».
/// Часы симулятора при этом заморожены
/// (`simctl status_bar override --time 09:41`).
///
/// # Устройство
///
/// Каждый тест — один экран и **два запуска подряд**: AX5, потом
/// обычный. AX5 идёт первым нарочно: он предмет, и если дорога
/// развалится посередине, потерян будет контроль, а не предмет.
///
/// `continueAfterFailure = true`, и кадр снимается **всегда**, в том
/// числе после неудачной дороги. Кадр, снятый не на том экране, видно
/// глазами; отсутствие кадра неотличимо от «тест не дошёл».
///
/// > Отказ отрисовки в этом проекте приходит В ВИДЕ КАДРА (замер
/// > 25.10.2026 на `ImageRenderer`: 402×760 с одним знаком запрета
/// > при зелёном прогоне). Поэтому приёмка набора — **взгляд
/// > на каждый кадр**, а не его существование.
///
/// Кадры ложатся в `build/кадры-ax5/`; то, что надо сохранить,
/// выносится в `Дизайн/кадры-приёмки/крупный-кегль-25.10/` отдельным
/// коммитом.
nonisolated final class КегльAX5: XCTestCase {

    static let AX5 = "UICTContentSizeCategoryAccessibilityXXXL"

    private var app: XCUIApplication!
    private var снято: [String] = []

    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-ax5")
    }

    override func setUp() {
        continueAfterFailure = true
        снято = []
    }

    /// Счёт печатается ВСЕГДА: «снято два» и «упал на первом, снято
    /// ноль» выглядят в логе одинаково — строк просто меньше,
    /// а их отсутствия никто не ищет.
    override func tearDown() {
        print("AX5-КАДРОВ СНЯТО: \(снято.count) · \(name) · \(снято.joined(separator: ", "))")
    }

    private func запустить(крупный: Bool, сценарий: String? = nil) {
        if app != nil { app.terminate() }
        app = XCUIApplication()
        var аргументы = ["-UITesting"]
        if let сценарий { аргументы += ["-Сценарий", сценарий] }
        if крупный { аргументы += ["-UIPreferredContentSizeCategoryName", Self.AX5] }
        app.launchArguments = аргументы
        app.launch()
        XCTAssertTrue(app.staticTexts["Стич"].firstMatch.waitForExistence(timeout: 60),
                      "приложение не дошло до «Сегодня» (крупный=\(крупный))")
    }

    private func снять(_ имя: String) {
        let кадр = app.screenshot()
        let вложение = XCTAttachment(screenshot: кадр)
        вложение.name = имя
        вложение.lifetime = .keepAlways
        add(вложение)
        do {
            try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
            try кадр.pngRepresentation.write(to: каталог.appendingPathComponent("\(имя).png"))
            снято.append(имя)
        } catch {
            print("AX5-КАДР НЕ ЛЁГ: \(имя) · \(error.localizedDescription)")
        }
    }

    /// Один экран, два кегля, один заход.
    private func пара(_ имя: String, сценарий: String? = nil,
                      дорога: @escaping (Bool) -> Void) {
        for крупный in [true, false] {
            let суффикс = крупный ? "ax5" : "обычный"
            запустить(крупный: крупный, сценарий: сценарий)
            дорога(крупный)
            снять("\(имя)-\(суффикс)")
        }
    }

    // MARK: - Дороги

    /// Шторка записи за круглой «+» в низу «Сегодня».
    private func открытьЗапись() -> Bool {
        let плюс = app.buttons["низ-записать"].firstMatch
        guard плюс.waitForExistence(timeout: 15) else {
            XCTFail("в низу «Сегодня» нет круглой «+» (`низ-записать`)")
            return false
        }
        плюс.tap()
        return app.staticTexts["Записать"].firstMatch.waitForExistence(timeout: 8)
    }

    /// Строка шторки по началу подписи. `identifier != "шапка-меню"` —
    /// не перестраховка: у шапки-меню озвучка «Ещё», и без этого
    /// условия тап уходит в меню настроек, а тест идёт дальше довольным
    /// (замер `ScreenshotTests.test04Занятие`).
    private func строкаЗаписи(_ начало: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@",
                        начало, "шапка-меню")
        ).firstMatch
    }

    /// Отметка «Пописал» в режиме выгула — по идентификатору и
    /// **запросом `.any`, а не `.buttons`**.
    ///
    /// Замер 25.10.2026, и он стоил прогона. Первая редакция спрашивала
    /// `app.buttons["отметка-urine"]` — форма взята у
    /// `DynamicTypeScreenshotTests:495`. Запрос не нашёл ничего
    /// **на обоих кеглях**, по 15 с каждый, а снятые кадры при этом
    /// показывают открытый режим выгула с кнопкой «Пописал» во всю
    /// ширину. Два нуля при живом предмете — это не «предмета нет»,
    /// а «вопрос не тот».
    ///
    /// Причина в `WalkMode:369`: у отметки стоит
    /// `.accessibilityElement(children: .ignore)` **без**
    /// `.accessibilityAddTraits(.isButton)`, то есть в дереве
    /// доступности она лежит как `Other`, а не `Button`. Живой контроль
    /// того же замера — `ScreenshotTests:324`, который спрашивает
    /// `descendants(matching: .any).matching(identifier:)` и работает.
    ///
    /// > Отсюда следствие не про мой набор: **`DynamicTypeScreenshotTests
    /// > .testXL13РежимВыгула` красен этой же строкой** — он ищет
    /// > `app.buttons[WalkModeИмена.urine]`. Проверено отдельным
    /// > прогоном, не выведено.
    private func отметкаПописал() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "отметка-urine").firstMatch
    }

    /// Вкладка собаки берётся по ПОРЯДКУ: её имя — кличка, то есть данные.
    private func вкладкаСобаки() -> Bool {
        let бар = app.tabBars.firstMatch
        guard бар.waitForExistence(timeout: 15) else {
            XCTFail("таб-бара нет")
            return false
        }
        бар.buttons.element(boundBy: 1).tap()
        return true
    }

    // MARK: - Экраны

    func test01Сегодня() {
        пара("01-сегодня") { _ in }
    }

    func test01bСегодняНиз() {
        пара("01b-сегодня-низ") { _ in
            self.app.swipeUp()
        }
    }

    func test02Семья() {
        пара("02-семья") { _ in
            guard self.вкладкаСобаки() else { return }
            let строка = self.найти("Семья и дежурство", в: self.app)
            guard строка.waitForExistence(timeout: 15) else {
                XCTFail("во вкладке собаки нет строки «Семья и дежурство»")
                return
            }
            строка.tap()
            XCTAssertTrue(self.app.navigationBars["Семья"].waitForExistence(timeout: 15),
                          "строка нажата, а экран «Семья» не открылся")
        }
    }

    func test03Питание() {
        пара("03-питание") { _ in
            guard self.вкладкаСобаки() else { return }
            let питание = self.app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Питание")).firstMatch
            guard питание.waitForExistence(timeout: 15) else {
                XCTFail("во вкладке собаки нет строки «Питание»")
                return
            }
            питание.tap()
            _ = self.app.navigationBars.firstMatch.waitForExistence(timeout: 10)
        }
    }

    /// Вкладка условная: `RootView:46` показывает её только при
    /// `isOnTreatment == true`. Сценарий `amber` его ставит
    /// (`SeedData:376`).
    func test04Здоровье() {
        пара("04-здоровье", сценарий: "amber") { _ in
            let вкладка = self.app.tabBars.buttons["Здоровье"]
            guard вкладка.waitForExistence(timeout: 15) else {
                XCTFail("вкладки «Здоровье» нет даже на сценарии `amber`")
                return
            }
            вкладка.tap()
            _ = self.app.navigationBars["Здоровье"].waitForExistence(timeout: 10)
        }
    }

    /// «+» → «Ещё» → «Занятие · N мин».
    func test05Занятие() {
        пара("05-занятие") { _ in
            guard self.открытьЗапись() else {
                XCTFail("шторка «Записать» не поднялась")
                return
            }
            let ещё = self.строкаЗаписи("Ещё")
            guard ещё.waitForExistence(timeout: 8) else {
                XCTFail("в шторке «Записать» нет строки «Ещё» — занятие за ней")
                return
            }
            ещё.tap()
            let занятие = self.app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Занятие")).firstMatch
            guard занятие.waitForExistence(timeout: 8) else {
                XCTFail("в шторке «Ещё» нет строки «Занятие»")
                return
            }
            занятие.tap()
            XCTAssertTrue(self.app.staticTexts["Он сделал"].waitForExistence(timeout: 8),
                          "занятие открылось не то: кнопки разметки на экране нет")
        }
    }

    /// Режим выгула. Якорь — ИДЕНТИФИКАТОР `отметка-urine`: пока
    /// прогулка идёт, «Пописал» лежит в дереве ДВАЖДЫ (в шторке выгула
    /// и в низу «Сегодня» под ней), и `firstMatch` по подписи берёт
    /// нижнюю (замер 24.10.2026).
    func test06РежимВыгула() {
        пара("06-выгул") { _ in
            let гулять = self.app.buttons["Гулять"].firstMatch
            let открыть = self.app.buttons["Открыть"].firstMatch
            if гулять.waitForExistence(timeout: 15) {
                гулять.tap()
                let пошли = self.app.buttons["Пошли"].firstMatch
                guard пошли.waitForExistence(timeout: 8) else {
                    XCTFail("«Гулять» нажата, а шторка с «Пошли» не поднялась")
                    return
                }
                пошли.tap()
            } else if открыть.waitForExistence(timeout: 5) {
                открыть.tap()
            } else {
                XCTFail("на «Сегодня» нет ни «Гулять», ни «Открыть»")
                return
            }
            XCTAssertTrue(self.отметкаПописал().waitForExistence(timeout: 15),
                          "режим выгула не открылся: кнопки `отметка-urine` в дереве нет")
        }
    }

    /// Худший случай ряда органов выгула: на паузе подпись кнопки
    /// становится «Продолжить» — вдвое длиннее «Паузы».
    func test06bВыгулПауза() {
        пара("06b-выгул-пауза") { _ in
            let гулять = self.app.buttons["Гулять"].firstMatch
            if гулять.waitForExistence(timeout: 15) {
                гулять.tap()
                let пошли = self.app.buttons["Пошли"].firstMatch
                if пошли.waitForExistence(timeout: 8) { пошли.tap() }
            } else {
                let открыть = self.app.buttons["Открыть"].firstMatch
                if открыть.waitForExistence(timeout: 5) { открыть.tap() }
            }
            guard self.отметкаПописал().waitForExistence(timeout: 15) else {
                XCTFail("режим выгула не открылся")
                return
            }
            let пауза = self.app.buttons["Пауза"].firstMatch
            guard пауза.waitForExistence(timeout: 8) else {
                XCTFail("кнопки «Пауза» нет — худший случай ряда не снят")
                return
            }
            пауза.tap()
            XCTAssertTrue(self.app.buttons["Продолжить"].firstMatch.waitForExistence(timeout: 8),
                          "«Пауза» нажата, а подпись не сменилась на «Продолжить»")
        }
    }

    func test07Пейволл() {
        пара("07-пейволл") { _ in
            guard self.открытьНастройки(в: self.app) else {
                XCTFail("в настройки не попали")
                return
            }
            let pro = self.app.buttons.containing(
                NSPredicate(format: "label CONTAINS 'Togo Pro'")).firstMatch
            guard pro.waitForExistence(timeout: 15) else {
                XCTFail("в настройках нет кнопки «Togo Pro»")
                return
            }
            pro.tap()
            // Якорь на ЗАГОЛОВКЕ: подзаголовок несёт вычисляемое число
            // (решение дизайна 25.10, круг 6 п. 9), и к вопросу
            // «открылся ли пейволл» состав Pro отношения не имеет.
            XCTAssertTrue(self.app.staticTexts["Togo Pro"].waitForExistence(timeout: 15),
                          "пейволл не открылся")
        }
    }

    func test08Настройки() {
        пара("08-настройки") { _ in
            guard self.открытьНастройки(в: self.app) else {
                XCTFail("в настройки не попали")
                return
            }
            XCTAssertTrue(self.app.navigationBars["Настройки"].waitForExistence(timeout: 15),
                          "экран настроек не открылся")
        }
    }

    // MARK: - Достижимость низа

    /// **«Карточку подрезает кнопка» и «карточку НЕ ДОСТАТЬ» — разные
    /// утверждения, и кадр сверху их не различает.**
    ///
    /// Набор 25.10 назвал дефектом на «Семье» и «Занятии» то, что
    /// закреплённая внизу кнопка лежит поверх карточки. Но оба экрана
    /// прокручиваются, а `TGScreen` держит под панелью запас её
    /// ИЗМЕРЕННОЙ высоты (`TGScaffolds:177`). Значит кадр сверху
    /// показывает ровно то, что показывает всякий экран с плавающей
    /// панелью, пока его не пролистали, — и вывод «содержимое
    /// потеряно» из него не следует.
    ///
    /// Эти два теста снимают те же экраны ПРОЛИСТАННЫМИ ДО УПОРА.
    /// Если низ достаётся — дефект не в раскладке, а в том, что
    /// у панели `TGScreen` нет подложки, и это решение дизайна
    /// (записано в самом каркасе, `TGScaffolds:166`). Если не
    /// достаётся — это потеря содержимого, и чинить надо немедленно.
    private func пролистатьДоУпора() {
        // Трижды, а не один раз: один `swipeUp` на доступном кегле
        // проходит меньше экрана, а содержимому здесь хватает трёх.
        for _ in 0..<3 {
            app.swipeUp()
        }
    }

    func test09СемьяНизДостижим() {
        пара("09-семья-низ") { _ in
            guard self.вкладкаСобаки() else { return }
            let строка = self.найти("Семья и дежурство", в: self.app)
            guard строка.waitForExistence(timeout: 15) else {
                XCTFail("во вкладке собаки нет строки «Семья и дежурство»")
                return
            }
            строка.tap()
            guard self.app.navigationBars["Семья"].waitForExistence(timeout: 15) else {
                XCTFail("строка нажата, а экран «Семья» не открылся")
                return
            }
            self.пролистатьДоУпора()
        }
    }

    func test10ЗанятиеНизДостижим() {
        пара("10-занятие-низ") { _ in
            guard self.открытьЗапись() else {
                XCTFail("шторка «Записать» не поднялась")
                return
            }
            let ещё = self.строкаЗаписи("Ещё")
            guard ещё.waitForExistence(timeout: 8) else {
                XCTFail("в шторке «Записать» нет строки «Ещё»")
                return
            }
            ещё.tap()
            let занятие = self.app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Занятие")).firstMatch
            guard занятие.waitForExistence(timeout: 8) else {
                XCTFail("в шторке «Ещё» нет строки «Занятие»")
                return
            }
            занятие.tap()
            guard self.app.staticTexts["Он сделал"].waitForExistence(timeout: 8) else {
                XCTFail("занятие открылось не то")
                return
            }
            self.пролистатьДоУпора()
        }
    }

    // MARK: - Ряд из трёх чисел: два подэкрана настроек

    /// Докрутить до элемента. Своя копия, а не общий помощник: на AX5
    /// один `swipeUp` проходит меньше экрана, и число шагов здесь
    /// задаётся под доступный кегль, а не под обычный.
    @discardableResult
    private func докрутить(до элемент: XCUIElement, шагов: Int = 8) -> Bool {
        for _ in 0..<шагов {
            if элемент.exists && элемент.isHittable { return true }
            app.swipeUp()
        }
        return элемент.exists && элемент.isHittable
    }

    /// Докрутить до ПОДПИСИ ряда чисел и сказать вслух, дошли ли.
    ///
    /// **Предмет этих тестов — подпись под числом, а не экран.**
    /// Кадр экрана, на котором ряда не видно, зелёного прогона
    /// не портит и выглядит снятой партией: первый заход 26.10
    /// так и вышел — восемь кадров, четыре экрана, ряда ни на одном.
    ///
    /// Поэтому прокрутка целится в саму подпись, а исход печатается
    /// числом: «дошли» и «не дошли» в логе обязаны различаться,
    /// иначе смотреть кадр пойдёт не тот и не тогда.
    /// Условие — `isHittable`, а НЕ `exists`.
    ///
    /// **`exists` отвечает про ДЕРЕВО и истинно для элемента, уехавшего
    /// за край экрана.** Замер 26.10.2026, на себе: первая редакция
    /// спрашивала `exists`, печатала «подпись „из 120 съел" на
    /// экране=true» — и **не прокручивала ни разу**, потому что условие
    /// выполнялось сразу. На кадре при этом верх «Сегодня»: герой
    /// и лента, ряда нет. Прогон зелёный, счёт кадров верный, предмета
    /// на кадрах ноль.
    ///
    /// > Тот же прокси в тот же день поймал и сосед по смене
    /// > (`УзкийЭкранОнбординг`): `exists=true` при кадрах ДО и ПОСЛЕ
    /// > шести свайпов, совпавших побайтово.
    ///
    /// `isHittable` отвечает про попадание пальцем, то есть про
    /// видимость, — это и есть вопрос кадра.
    @discardableResult
    private func докрутитьДоПодписи(_ подпись: String, шагов: Int = 8) -> Bool {
        let цель = app.staticTexts[подпись].firstMatch
        func видна() -> Bool { цель.exists && цель.isHittable }
        var дошли = видна()
        var шаг = 0
        while !дошли && шаг < шагов {
            app.swipeUp()
            шаг += 1
            дошли = видна()
        }
        print("AX5-РЯД: подпись «\(подпись)» ВИДНА=\(дошли) · шагов \(шаг) · "
              + "в дереве=\(цель.exists)")
        if !дошли {
            print("AX5-РЯД-ОТКАЗ: до «\(подпись)» не докрутили за \(шагов) шагов — "
                  + "кадр снят, но предмета на нём может не быть")
        }
        return дошли
    }

    /// Экран «Данные и приватность» — третье из семи мест `РядЧисел`
    /// (`DataPrivacyScreen.swift:25`): записей · собак · дней.
    ///
    /// Ось приёмки `475072b` дословно: на обычном кегле вид не меняется,
    /// на AX5 ряд становится столбцом. Снимается ПАРОЙ в одном заходе,
    /// иначе «столбец» не отличить от «так было всегда».
    func test11ДанныеИПриватность() {
        пара("11-данные") { крупный in
            guard self.открытьНастройки(в: self.app) else {
                XCTFail("в настройки не попали (крупный=\(крупный))")
                return
            }
            let строка = self.app.buttons["Данные и приватность"].firstMatch
            guard self.докрутить(до: строка) else {
                XCTFail("в настройках нет строки «Данные и приватность» даже после прокрутки")
                return
            }
            строка.tap()
            guard self.app.staticTexts["Всё лежит на телефоне"].waitForExistence(timeout: 15) else {
                XCTFail("строка нажата, а экран «Данные» не открылся")
                return
            }
            // ДОКРУТИТЬ ДО САМОГО РЯДА. Первый заход 26.10 снял этот
            // экран без прокрутки — и ряда на кадре не оказалось ни
            // на одном кегле: на AX5 его уносит ниже сгиба абзац
            // «Аккаунта нет, серверов у нас нет…». Кадр был, предмета
            // на кадре не было, а прогон зелёный.
            // Цель — форма «one»: собака в засеве одна.
            //
            // **Первый заход 26.10 целился в «собак» и промахнулся
            // на обоих кеглях.** Подпись `TGStat(count:сЧислом:)`
            // получается вычитанием числа из локализованной строки
            // (`TGRows:190`), то есть несёт РУССКУЮ ФОРМУ МНОЖЕСТВЕННОГО
            // ЧИСЛА: при `count == 1` это «собака», а не «собак».
            // Промах дал `false` при живом ряде — отчёт о моём запросе,
            // выданный было за факт об экране.
            self.докрутитьДоПодписи("собака")
        }
    }

    /// Экран «Журнал действий» — седьмое из семи мест
    /// (`UsageLogScreen.swift:78`): всего · записей · заходов.
    func test12ЖурналДействий() {
        пара("12-журнал-действий") { крупный in
            guard self.открытьНастройки(в: self.app) else {
                XCTFail("в настройки не попали (крупный=\(крупный))")
                return
            }
            let строка = self.app.buttons["Журнал действий"].firstMatch
            guard self.докрутить(до: строка) else {
                XCTFail("в настройках нет строки «Журнал действий» даже после прокрутки")
                return
            }
            строка.tap()
            guard self.app.navigationBars["Журнал действий"].waitForExistence(timeout: 15) else {
                XCTFail("строка нажата, а экран «Журнал действий» не открылся")
                return
            }
            // ЗАМЕР, А НЕ ПРОВЕРКА. На стенде журнал выключен и пуст,
            // и `UsageLogScreen:21` при `report.isEmpty` рисует плашку
            // «Журнал пока пуст» ВМЕСТО блока `summary`, в котором
            // и лежит ряд. То есть ряда здесь нет ни на каком кегле,
            // и кадр это показывает — он улика, а не приёмка.
            let ряд = self.докрутитьДоПодписи("записей")
            print("AX5-ЗАМЕР: ряд «Журнала действий» достижим=\(ряд). "
                  + "Ложь ожидаема: журнал выключен, report.isEmpty истинно.")
        }
    }

    /// Первое из семи мест — `TodaySummaryStrip` на главном экране
    /// (`TodayScreen.swift:1167`): съел · кормлений · выходов.
    ///
    /// Отдельным тестом от `test01Сегодня`, а не правкой его: тот
    /// снимает ВЕРХ «Сегодня» и служит эталоном сравнения другим
    /// партиям. Ряд живёт ниже героя и ленты событий — на обычном
    /// кегле ниже сгиба, на AX5 намного ниже.
    func test13СегодняРядЧисел() {
        пара("13-сегодня-ряд") { _ in
            // Цель — подпись ПЕРВОГО числа, «из 120 съел»: она
            // единственная в ряду без формы множественного числа
            // (`TodaySummaryStrip:25`, ветка `dailyGrams > 0`).
            // У соседей формы плавают: «1 кормление», «2 выхода».
            //
            // И прокрутка ОСТАНАВЛИВАЕТСЯ на цели, а не идёт до упора:
            // первый заход с десятью шагами ряд ПРОЛИСТАЛ — на кадре
            // оказался «план дня» ниже него. Перелёт и недолёт дают
            // одинаково пустой кадр.
            self.докрутитьДоПодписи("из 120 съел", шагов: 10)
        }
    }

    /// Пятое из семи — `WalkMode.statsCard` (`WalkMode.swift:844`):
    /// в пути · раз пописал · стул.
    ///
    /// **Он живёт НЕ в режиме выгула, а в шторке итога «Погуляли»**
    /// (`WalkMode:774`), и у неё есть ворота: `показатьИтог(_:)`
    /// закрывает прогулку молча, если не было ни срыва, ни инцидента,
    /// ни заметки. Поэтому дорога обязана поставить отметку — иначе
    /// шторка не откроется, и «ряда нет» будет отчётом о воротах,
    /// а не о раскладке.
    ///
    /// «Домой» — СЛАЙДЕР (`WalkControls.swift`), а не кнопка:
    /// `DragGesture(minimumDistance: 1)`, а в дерево он подан как
    /// кнопка (`.accessibilityAddTraits(.isButton)`
    /// плюс `.accessibilityAction`). Поэтому сперва свайп, потом тап,
    /// и при обоих неудачах — кадр отказа: «шторка не открылась»
    /// и «открылась без ряда» снаружи неразличимы.
    func test14ИтогПрогулкиРядЧисел() {
        пара("14-итог-прогулки") { крупный in
            let гулять = self.app.buttons["Гулять"].firstMatch
            if гулять.waitForExistence(timeout: 15) {
                гулять.tap()
                let пошли = self.app.buttons["Пошли"].firstMatch
                if пошли.waitForExistence(timeout: 8) { пошли.tap() }
            } else {
                let открыть = self.app.buttons["Открыть"].firstMatch
                if открыть.waitForExistence(timeout: 5) { открыть.tap() }
            }
            guard self.отметкаПописал().waitForExistence(timeout: 15) else {
                XCTFail("режим выгула не открылся (крупный=\(крупный))")
                return
            }
            // Отметка, без которой ворота итога закроют прогулку молча.
            let сорвался = self.app.buttons["Сорвался"].firstMatch
            if сорвался.waitForExistence(timeout: 8) {
                сорвался.tap()
            } else {
                print("AX5-ЗАМЕР: кнопки «Сорвался» нет — ворота итога могут закрыть прогулку")
            }

            let домой = self.app.buttons["Домой"].firstMatch
            guard домой.waitForExistence(timeout: 10) else {
                XCTFail("слайдера «Домой» нет — прогулку нечем закончить")
                return
            }
            домой.swipeRight()
            if !self.app.staticTexts["Погуляли"].waitForExistence(timeout: 8) {
                домой.tap()
            }
            guard self.app.staticTexts["Погуляли"].waitForExistence(timeout: 10) else {
                // Кадр снимается `пара` в любом случае — здесь только
                // имя причины, чтобы читающий лог не искал её в коде.
                print("AX5-ЗАМЕР: шторка «Погуляли» не открылась ни свайпом, ни тапом — "
                      + "ряд statsCard этим заходом НЕ СНЯТ")
                XCTFail("шторка итога «Погуляли» не открылась — statsCard не снят")
                return
            }
            self.докрутитьДоПодписи("в пути")
        }
    }
}
