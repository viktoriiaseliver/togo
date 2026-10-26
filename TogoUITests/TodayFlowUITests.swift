import XCTest

/// Дымовые UI-тесты: проверяют не вёрстку, а то, что путь от главного экрана
/// к записи вообще проходится и что обещания продукта видны на экране.
nonisolated final class TodayFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
    }

    func testГлавныйЭкранПоказываетСобакуИКнопки() {
        XCTAssertTrue(app.staticTexts["Стич"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Просится"].firstMatch.exists, "«Просится» — главная кнопка, она всегда на месте")
        XCTAssertTrue(app.buttons["Гулять"].exists)
        XCTAssertTrue(app.buttons["Ещё"].exists)
    }

    /// **Вкладка «Здоровье» держит ПРАВО, а не курс лечения** — решение
    /// Виктории 08.10.2026, коммит `02c1e88` («закрыта правом И ТОЛЬКО
    /// правом»): пока условие стояло на `isOnTreatment`, вкладка исчезала
    /// ровно в день конца курса — когда нужен отчёт врачу.
    ///
    /// Прежде этот тест утверждал обратное: `XCTAssertFalse(«Здоровье»)`
    /// с подписью «у здоровой собаки медицины на главном нет вовсе».
    /// Он был красным **тринадцать дней** — с правки 08.10 до первого
    /// полного UI-прогона 21.10.2026, — и никто этого не знал, потому
    /// что UI-набор не гоняли. Правка `0a8267d` (20.10) сняла восемь
    /// таких обещаний в текстах, головах модулей, документах и на сайте;
    /// **UI-набор в тот день не прогоняли, и это осталось.**
    ///
    /// > Имя теста — утверждение о поведении, и стареет оно молча.
    /// > Старое имя врало в обе стороны: обещало четыре вкладки при пяти
    /// > и отсутствие медицины при живом праве.
    ///
    /// Условие показа держат `MedicalAccessTests` (краснеют на возврате
    /// `isOnTreatment`); здесь — только то, что человек видит на панели.
    /// **Вкладок теперь ЧЕТЫРЕ, и «Семья» уехала во вкладку собаки** —
    /// решение Виктории 22.10.2026 (`design_handoff_togo_ios28`,
    /// «Навигация (решено)»). Имя теста переписано вместе с телом:
    /// предыдущее («Пять вкладок…») было бы ложным с первого прогона,
    /// а у этого набора уже есть история имени, врущего тринадцать
    /// дней при верном теле.
    func testЧетыреВкладкиИЗдоровьеДержитПраво() {
        XCTAssertTrue(app.tabBars.buttons["Сегодня"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["История"].exists)
        XCTAssertTrue(app.tabBars.buttons["Стич"].exists,
                      "всё про собаку — своя вкладка, а не четыре уровня в шторке")
        XCTAssertTrue(app.tabBars.buttons["Здоровье"].exists,
                      "«Здоровье» открыто правом .seeMedical, а не курсом: решение 08.10.2026")

        // Утверждение от ОБРАТНОГО, а не просто снятая строка: если
        // вкладку когда-нибудь вернут, этот тест обязан покраснеть.
        // Снять проверку значило бы оставить место, где пятая вкладка
        // вернётся молча.
        XCTAssertFalse(app.tabBars.buttons["Семья"].exists,
                       "«Семья» — первая строка вкладки собаки, а не вкладка: решение 22.10.2026")

        // И проверка, что набору было что проверять: без неё обе
        // половины зеленели бы на непоявившейся панели вкладок.
        XCTAssertEqual(app.tabBars.buttons.count, 4,
                       "вкладок должно быть ровно четыре, а найдено \(app.tabBars.buttons.count)")
    }

    func testВердиктПредлагаетВывестиПервойКнопкой() {
        app.buttons["Просится"].firstMatch.tap()
        let вывожу = app.buttons["Вывожу"]
        XCTAssertTrue(вывожу.waitForExistence(timeout: 3),
                      "«Вывожу» стоит первой во всех четырёх исходах вердикта")
    }

    /// Запись еды доходит до ленты.
    ///
    /// **Дорога изменилась 24.10.2026: `ActionGrid` удалён**, и кнопки
    /// «Еда» прямо на главном больше нет. Еда записывается из шторки
    /// «Записать» («+», крючок `низ-записать`, строка «Еда» —
    /// `TodayBottom`). Отказ звучал «Failed to tap "Еда" Button»
    /// и читался как дефект продукта.
    func testЗаписьЕдыПоявляетсяВЛенте() {
        let плюс = app.buttons["низ-записать"].firstMatch
        XCTAssertTrue(плюс.waitForExistence(timeout: 10), "кнопки «Записать» нет")
        плюс.tap()
        let еда = найти("Еда", в: app)
        XCTAssertTrue(еда.waitForExistence(timeout: 5),
                      "в шторке «Записать» нет строки «Еда»")
        еда.tap()
        let записать = app.buttons["Записать"]
        XCTAssertTrue(записать.waitForExistence(timeout: 3))
        записать.tap()
        XCTAssertTrue(app.buttons["Отменить"].waitForExistence(timeout: 3),
                      "каждая запись отменяется тостом")
    }

    /// Дорога App Review до политики и условий — целиком, а не по частям.
    ///
    /// **Правка 24.10.2026.** Политика и условия больше не лежат строками
    /// в настройках: четыре правовые строки собраны в экран «Правила»
    /// (эталон `v10-прототип-24.10/screenshots/47-screens.jpg`). Тест,
    /// искавший их прямо в настройках, после этого покраснел бы — и
    /// покраснел бы **верно**: дорога правда изменилась.
    ///
    /// Поэтому он теперь её и проходит — открывает «Правила» и смотрит
    /// внутрь. Проверять наличие строки на экране, с которого она ушла,
    /// значит стеречь прокси вместо предмета: предмет здесь — «ревьюер
    /// Apple доходит до политики», а не «строка лежит в том же списке».
    func testНастройкиСодержатОбязательныеРазделы() {
        XCTAssertTrue(открытьНастройки(в: app), "в настройки не попасть")
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))

        let данные = app.descendants(matching: .any)
            .matching(identifier: "Данные и приватность").firstMatch
        if !данные.exists { app.swipeUp() }
        XCTAssertTrue(данные.waitForExistence(timeout: 3),
                      "«Данные и приватность» — обязательный раздел для App Store")

        let правила = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Правила")
        ).firstMatch
        for _ in 0..<10 where !правила.exists { app.swipeUp() }
        XCTAssertTrue(правила.waitForExistence(timeout: 3),
                      "в настройках нет строки «Правила» — за ней политика и условия")
        правила.tap()
        XCTAssertTrue(app.navigationBars["Правила"].waitForExistence(timeout: 5),
                      "строка «Правила» есть, а экран за ней не открылся")

        for раздел in ["Политика конфиденциальности", "Условия"] {
            let элемент = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", раздел)
            ).firstMatch
            if !элемент.exists { app.swipeUp() }
            XCTAssertTrue(элемент.waitForExistence(timeout: 3),
                          "\(раздел) — обязательный раздел для App Store")
        }
    }
}
