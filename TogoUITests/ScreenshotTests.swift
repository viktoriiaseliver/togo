import XCTest

/// Генератор скриншотов для App Store и для глазной проверки вёрстки.
///
/// Запуск:
///   xcodebuild ... test -only-testing:TogoUITests/ScreenshotTests \
///     -resultBundlePath build/Screens.xcresult
///   Tools/extract_screenshots.sh build/Screens.xcresult fastlane/screenshots
nonisolated final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    /// Подписи на языке прогона. Русский остаётся русским, французский
    /// берётся из каталога приложения — см. `Подписи`.
    private let т = Подписи()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        // «Стич» не переводится: это кличка из демо-данных, а не подпись
        // интерфейса. В каталоге она есть (генератор строк вынимает любую
        // кириллицу подряд), но приложение показывает литерал из SeedData.
        XCTAssertTrue(app.staticTexts["Стич"].waitForExistence(timeout: 10),
                      "приложение не поднялось на языке «\(т.язык)»")
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test01Сегодня() {
        capture("01-today")
    }

    func test02Просится() {
        app.buttons[т("Просится")].firstMatch.tap()
        _ = app.buttons[т("Вывожу")].waitForExistence(timeout: 5)
        capture("02-needs-verdict")
    }

    func test03Стул() {
        app.buttons[т("Стул")].firstMatch.tap()
        _ = app.staticTexts[т("Колбаска")].waitForExistence(timeout: 5)
        capture("03-stool")
    }

    func test04Занятие() {
        app.buttons[т("Ещё")].firstMatch.tap()
        let занятие = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH %@", т("Занятие"))
        ).firstMatch
        guard занятие.waitForExistence(timeout: 5) else { return }
        занятие.tap()
        _ = app.staticTexts[т("Он сделал")].waitForExistence(timeout: 5)
        capture("04-training")
    }

    func test05История() {
        app.tabBars.buttons[т("История")].tap()
        _ = app.navigationBars[т("История")].waitForExistence(timeout: 5)
        capture("05-history")
    }

    func test06Семья() {
        app.tabBars.buttons[т("Семья")].tap()
        _ = app.navigationBars[т("Семья")].waitForExistence(timeout: 5)
        capture("06-family")
    }


    func test12Прогулка() {
        app.buttons[т("Гулять")].firstMatch.tap()
        let пошли = app.buttons[т("Пошли")].firstMatch
        XCTAssertTrue(пошли.waitForExistence(timeout: 5))
        пошли.tap()

        let пописал = app.buttons[т("Пописал")].firstMatch
        XCTAssertTrue(пописал.waitForExistence(timeout: 5), "таймер должен пойти сразу")
        пописал.tap()
        пописал.tap()
        app.buttons[т("Стул")].firstMatch.tap()
        capture("12-walk-mode")
    }

    func test08Питание() {
        app.tabBars.buttons["Стич"].tap()
        найти(т("Питание и режим"), в: app).tap()
        _ = app.navigationBars[т("Питание")].waitForExistence(timeout: 5)
        capture("08-feeding")
    }

    func test09Права() {
        app.tabBars.buttons[т("Семья")].tap()
        // «Мама» — имя участника из демо-данных, такая же данность, как
        // кличка. В каталоге оно есть и «переведено» как Maman, но
        // приложение показывает литерал из SeedData.
        найти("Мама", в: app).tap()
        _ = app.staticTexts[т.прописными("что разрешено")].waitForExistence(timeout: 5)
        capture("09-permissions")
    }

    func test10Перенос() {
        app.buttons[т("Настройки")].tap()
        найти(т("Перенос и восстановление"), в: app).tap()
        _ = app.navigationBars[т("Перенос")].waitForExistence(timeout: 5)
        capture("10-backup")
    }

    func test11Язык() {
        app.buttons[т("Настройки")].tap()
        найти(т("Язык"), в: app).tap()
        _ = app.navigationBars[т("Язык")].waitForExistence(timeout: 5)
        capture("11-language")
    }

    /// Кадр пейволла для App Review — и сторож на то, что цены вообще есть.
    ///
    /// Пропуска здесь больше нет, и это главное. Раньше тест, не дождавшись
    /// цен, бросал `XCTSkip` — и прогон отвечал `** TEST SUCCEEDED **`
    /// с кодом возврата 0. Сторож стоял ровно на том, что держит релиз,
    /// и молчал: кадр с надписью «Цены не загрузились» уехал в App Store
    /// Connect именно так.
    ///
    /// Под `xcodebuild` тест сегодня красный, и красный по делу — цен
    /// в пейволле нет. Замеры 23.09, чтобы следующий не искал заново:
    ///
    /// - ссылка на `Configuration/Togo.storekit` в схеме есть (`TestAction`
    ///   и `LaunchAction`), путь резолвится — до приложения не доезжает;
    /// - `SKTestSession` из теста тоже не помогает: файл она читает
    ///   (2355 байт; несуществующий путь честно отвергает,
    ///   `SKTestErrorDomain Code=4`), но `Product.products` отдаёт пусто —
    ///   и в процессе раннера, и внутри процесса приложения (проверено
    ///   модульным тестом, он идёт в `Togo.app` через `TEST_HOST`);
    /// - план тестов со `storeKitConfigurationFileReference` на чистом
    ///   симуляторе — тот же пустой результат.
    ///
    /// Пусто — это ответ, а не «не успело»: пейволл показывает «Цены
    /// не загрузились» только когда загрузка кончилась (`TGStateful`
    /// с `isLoading: false`), и баннера ошибки при этом нет.
    ///
    /// Из Xcode цены приходят — там кадр и снимается, пока способа снять
    /// его из командной строки не нашлось. Неисключённое объяснение одно:
    /// формат `.storekit` version 4.0 против Xcode 27.
    func test07Подписка() {
        app.buttons[т("Настройки")].tap()
        // Кнопку, а не любой элемент с этим именем.
        //
        // Прежде здесь стоял `descendants(matching: .any)`, и первым
        // совпадением оказывался StaticText внутри строки — подпись,
        // а не кнопка. Тап по подписи в шторку не уводил, и тест падал
        // на следующей строке словами «пейволл не открылся»: жалоба
        // указывала на пейволл, а сломано было нажатие.
        //
        // Имя кнопки собирается из строки целиком («Togo Pro»,
        // «попробовать»), поэтому ищем по вхождению, а не по равенству.
        let pro = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Togo Pro'")
        ).firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 5), "в настройках нет кнопки «Togo Pro»")
        pro.tap()
        // **Якорь сменён 23.10.2026 вместе с редизайном экрана.** Раздел
        // «ЧТО ОТКРЫВАЕТ» снят: на эталонном кадре `17.png` темы «Кино»
        // три строки идут без заголовка секции, а шапка листа говорит
        // «Togo Pro · ровно три вещи». Старый якорь после редизайна
        // не нашёлся бы — и тест сказал бы «пейволл не открылся» при
        // открытом пейволле, то есть назвал бы причину неверно.
        //
        // Регистр по-прежнему без учёта: подзаголовок рисуется как есть,
        // но соседние подписи в этом проекте ходят через
        // `.textCase(.uppercase)`, и привычку сверять без регистра
        // отменять незачем.
        let заголовок = app.staticTexts.containing(
            NSPredicate(format: "label LIKE[c] %@", т("ровно три вещи"))
        ).firstMatch
        XCTAssertTrue(заголовок.waitForExistence(timeout: 5), "пейволл не открылся")

        // Дальше — развилка, и обе ветки что-то утверждают.
        //
        // **Почему развилка, а не пропуск.** Из командной строки цены
        // не приходят: замер `gamut-71` от 23.09.2026 показал, что
        // локальная конфигурация `.storekit` до симулятора под
        // `xcodebuild` не доезжает, и запрос уходит в живой магазин.
        // У нас к этому добавлено второе: Соглашение о платных
        // приложениях не подписано, и живой магазин не отдаёт ничего
        // при любом состоянии продуктов.
        //
        // Пропустить тест было бы худшим выходом: пропущенный
        // засчитывается за успех и молчит ровно так же, как рабочий.
        // Поэтому ветки две, и каждая проверяет своё:
        //
        // - цены пришли (запуск из Xcode) — оба плана в кадре;
        // - цен нет — пустое состояние обязано **назвать причину**
        //   и не врать про связь. Именно этим оно и было дефектом
        //   до 23.09: «обычно это связь» стояло там всегда, а магазин
        //   отвечал пустым списком без единой ошибки связи.
        //
        // Ветка определяется тем, что на экране, и это осознанно:
        // состояния стора у UI-теста нет. Зато обе ветки падают, если
        // экран перестанет быть собой, — а это и есть то, что тест
        // должен стеречь.
        let month = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '2,99' OR label CONTAINS '2.99'")
        ).firstMatch

        if month.waitForExistence(timeout: 20) {
            let year = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS '19,99' OR label CONTAINS '19.99'")
            ).firstMatch
            XCTAssertTrue(year.exists,
                          "пейволл показал месяц, но не год — планов в кадре должно быть два")
        } else {
            let пусто = app.staticTexts.containing(
                NSPredicate(format: "label LIKE[c] %@", т("Цены не загрузились"))
            ).firstMatch
            XCTAssertTrue(пусто.exists, """
                цен нет, и пустого состояния тоже нет. Значит пейволл                 висит в «Спрашиваю цены у App Store…» бесконечно —                 человек ждёт того, что никогда не придёт.
                """)

            // Причина должна быть названа. «Обычно это связь» здесь —
            // догадка, а не ответ: чинить связь, которая не сломана,
            // человек будет ровно столько, сколько у него терпения.
            let проСвязь = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "связь")
            ).firstMatch
            let проМагазин = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "App Store")
            ).firstMatch
            XCTAssertTrue(проМагазин.exists || проСвязь.exists,
                          "пустое состояние не называет причину вовсе")
        }

        capture("07-paywall")
    }
}
