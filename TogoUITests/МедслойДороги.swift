import XCTest

/// Дороги стенда к визитам, диагнозам и назначениям.
///
/// **Повод тот же, что у `Анализы.swift`, и он измерен.** 08.10.2026
/// три новых экрана уехали в git принятыми **компилятором и прогоном**:
/// место вызова есть, сторож зелёный, формы собираются. Расстановку
/// и слова на них не видел никто, и снять было нечем — UI-тестов,
/// проходящих по этим дорогам, ноль.
///
/// > **Три новых экрана без кадра — это три поверхности, про которые
/// > завтра будут думать, что они приняты.** Зелёный сторож на вызов
/// > этому способствует: он говорит «дорога есть» и молчит о том,
/// > что по ней видно.
///
/// Файл ничего не утверждает про цвет и расстановку — он доводит
/// приложение до состояний и кладёт кадры файлами. Судит человек.
///
/// Приёмка каждой дороги двойная: кадр показывает ПОКАЗ, а проверка
/// «запись появилась в списке» — что форма дошла до хранилища. Второго
/// кадр не видит: три шага или одна шторка могут собрать черновик
/// и не позвать `context.insert`.
nonisolated final class МедслойДороги: XCTestCase {

    private var app: XCUIApplication!

    private var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-медслоя")
    }

    /// Суффикс партии приходит СНАРУЖИ и только с приставкой
    /// `TEST_RUNNER_` — `xcodebuild` своё окружение процессу теста
    /// не передаёт. Замерено на `Анализы.swift`: без приставки прогон
    /// проходит, кадры снимаются и **имена у них без суффикса**, то есть
    /// вторая партия перезаписывает первую молча.
    ///
    ///     TEST_RUNNER_KADR_SUFFIX=light xcodebuild … -only-testing:TogoUITests/МедслойДороги
    private var суффикс: String {
        let значение = ProcessInfo.processInfo.environment["KADR_SUFFIX"] ?? ""
        return значение.isEmpty ? "" : "-\(значение)"
    }

    /// Кадр файлом, не вложением: выгрузка вложений у нас не сработала
    /// пять раз из девяти. Отказ записи НЕ роняет тест — кадр это улика,
    /// а не ворота.
    @discardableResult
    private func снять(_ имя: String) -> URL? {
        let кадр = app.screenshot()
        do {
            try FileManager.default.createDirectory(at: каталог, withIntermediateDirectories: true)
            let путь = каталог.appendingPathComponent("\(имя)\(суффикс).png")
            try кадр.pngRepresentation.write(to: путь)
            print("КАДР: \(путь.path) · \(кадр.pngRepresentation.count) байт")
            return путь
        } catch {
            print("КАДР НЕ ЗАПИСАН: \(имя) · \(error)")
            return nil
        }
    }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-Сценарий", "amber"]
        app.launch()
    }

    private func докрутить(до элемент: XCUIElement, шагов: Int = 8) -> Bool {
        for _ in 0..<шагов {
            if элемент.exists && элемент.isHittable { return true }
            app.swipeUp()
        }
        return элемент.exists && элемент.isHittable
    }

    /// Дойти до раздела «Здоровья» по имени строки.
    /// Возвращает, дошли ли, — но кадр снимается у вызывающего ДО
    /// суждения, иначе при падении кадра не будет вовсе.
    private func открытьРаздел(_ имя: String) -> Bool {
        guard app.staticTexts["Стич"].firstMatch.waitForExistence(timeout: 20) else { return false }
        let вкладка = app.tabBars.buttons["Здоровье"]
        guard вкладка.waitForExistence(timeout: 15) else { return false }
        вкладка.tap()
        _ = app.navigationBars["Здоровье"].waitForExistence(timeout: 10)
        let строка = app.buttons[имя].firstMatch
        guard докрутить(до: строка) else { return false }
        строка.tap()
        return app.navigationBars[имя].waitForExistence(timeout: 10)
    }

    // MARK: Визиты

    func testДорогаКВизитамСнята() throws {
        let открылось = открытьРаздел("Визиты к врачу")
        снять("10-визиты-список")
        XCTAssertTrue(открылось, """
            до «Визитов к врачу» не дошли. Кадр 10 снят ДО этой проверки —
            на нём видно, где остановились: на «Здоровье» без строки
            или на экране, который не открылся.
            """)

        let добавить = app.buttons["Добавить визит"].firstMatch
        XCTAssertTrue(добавить.waitForExistence(timeout: 10),
                      "кнопки «Добавить визит» нет — ввод недостижим")
        добавить.tap()

        let врач = app.textFields["Врач"].firstMatch
        let формаОткрылась = врач.waitForExistence(timeout: 10)
        if формаОткрылась {
            врач.tap()
            врач.typeText("Кочубина")
        }
        снять("11-визит-форма")
        XCTAssertTrue(формаОткрылась, "форма визита не открылась — смотри кадр 11")

        app.buttons["Добавить"].firstMatch.tap()

        let вернулись = app.navigationBars["Визиты к врачу"].waitForExistence(timeout: 10)
        let появился = app.staticTexts["Кочубина"].firstMatch.waitForExistence(timeout: 10)
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Кочубина'")).firstMatch.exists
        снять("12-визиты-список-с-записью")
        XCTAssertTrue(вернулись, "после сохранения не вернулись к списку")
        XCTAssertTrue(появился, """
            визит не появился в списке. Форма собрала черновик и не дошла
            до хранилища — кадр этого не видит, и сторож на вызов тоже.
            """)
    }

    // MARK: Диагнозы

    func testДорогаКДиагнозамСнята() throws {
        let открылось = открытьРаздел("Диагнозы")
        снять("20-диагнозы-список")
        XCTAssertTrue(открылось, "до «Диагнозов» не дошли — смотри кадр 20")

        let добавить = app.buttons["Добавить диагноз"].firstMatch
        XCTAssertTrue(добавить.waitForExistence(timeout: 10),
                      "кнопки «Добавить диагноз» нет — ввод недостижим")
        добавить.tap()

        let формулировка = app.textFields["Формулировка"].firstMatch
        let формаОткрылась = формулировка.waitForExistence(timeout: 10)
        if формаОткрылась {
            формулировка.tap()
            формулировка.typeText("гипотиреоз")
        }
        снять("21-диагноз-форма")
        XCTAssertTrue(формаОткрылась, "форма диагноза не открылась — смотри кадр 21")

        app.buttons["Добавить"].firstMatch.tap()

        let вернулись = app.navigationBars["Диагнозы"].waitForExistence(timeout: 10)
        let появился = app.staticTexts["гипотиреоз"].firstMatch.waitForExistence(timeout: 10)
        снять("22-диагнозы-список-с-записью")
        XCTAssertTrue(вернулись, "после сохранения не вернулись к списку")
        XCTAssertTrue(появился, "диагноз не появился в списке — форма не дошла до хранилища")

        // Статус показан СЛОВОМ, а не только значком. Проверяется
        // здесь, а не кадром: цвет и форму судит человек, а наличие
        // слова — машина, и это та половина, которую машина может.
        XCTAssertTrue(app.staticTexts["рабочая гипотеза"].firstMatch.exists, """
            статуса диагноза нет СЛОВОМ в списке. Если он передаётся
            только значком или цветом — это дефект доступности:
            глиф для речи то же, что цвет для зрения.
            """)
    }

    // MARK: Назначения

    func testДорогаКНазначениямСнята() throws {
        let открылось = открытьРаздел("Назначения")
        снять("30-назначения-список")
        XCTAssertTrue(открылось, "до «Назначений» не дошли — смотри кадр 30")

        let добавить = app.buttons["Добавить назначение"].firstMatch
        XCTAssertTrue(добавить.waitForExistence(timeout: 10),
                      "кнопки «Добавить назначение» нет — ввод недостижим")
        добавить.tap()

        let препарат = app.textFields["Препарат"].firstMatch
        let формаОткрылась = препарат.waitForExistence(timeout: 10)
        if формаОткрылась {
            препарат.tap()
            препарат.typeText("Левотироксин")
            let номер = app.textFields["Номер"].firstMatch
            if номер.exists {
                номер.tap()
                номер.typeText("8935331")
            }
        }
        снять("31-назначение-форма")
        XCTAssertTrue(формаОткрылась, "форма назначения не открылась — смотри кадр 31")

        // Окно контроля считается и показывается ДО сохранения.
        // Если строки нет — либо срок не выбран по умолчанию, либо
        // `ControlWindow` вернул `nil`, и тогда человек сохранит рецепт
        // без срока, не узнав об этом.
        //
        // **Клавиатуру убираем ПЕРЕД поиском, и ищем по `exists`,
        // а не по `isHittable`.** Первая редакция делала наоборот
        // и дважды сняла кадр «окна-контроля-НЕТ» при живом окне:
        // поднятая клавиатура закрывала нижнюю часть формы, а подпись
        // внутри прокрутки не считается «достижимой», пока не видна.
        //
        // > **Проба, спрашивающая `isHittable` у ПОДПИСИ, отвечает
        // > не про существование, а про видимость в этот момент.**
        // > Для кнопки это верный вопрос, для текста — нет, и ответ
        // > «нет» читается как «в приложении этого нет».
        if app.keyboards.element.exists {
            app.buttons["Return"].firstMatch.tap()
        }
        let окно = app.staticTexts["Окно контроля"].firstMatch
        var нашли = окно.exists
        for _ in 0..<6 where !нашли {
            app.swipeUp()
            нашли = окно.exists
        }
        снять(нашли ? "32-назначение-окно-контроля" : "32-назначение-окна-контроля-НЕТ")
        XCTAssertTrue(нашли, """
            строки «Окно контроля» нет в форме назначения, хотя срок
            по умолчанию выбран («4–6 нед»). Значит `ControlWindow.window`
            вернул `nil` — и человек сохранит рецепт, не увидев, на какие
            даты придётся контроль. `ReminderScheduler` при этом возьмёт
            напоминание из тех же недель, то есть расхождение будет
            между тем, что показали, и тем, о чём напомнят.
            """)

        app.buttons["Добавить"].firstMatch.tap()

        let вернулись = app.navigationBars["Назначения"].waitForExistence(timeout: 10)
        let появилось = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '8935331'")).firstMatch.waitForExistence(timeout: 10)
        снять("33-назначения-список-с-записью")
        XCTAssertTrue(вернулись, "после сохранения не вернулись к списку")
        XCTAssertTrue(появилось, """
            назначение не появилось в списке. Это не только про показ:
            `ReminderScheduler` берёт напоминания о контроле ИЗ рецептов,
            и незаписанный рецепт означает, что напоминания не будет,
            а человек будет считать, что оно заведено.
            """)
    }
}
