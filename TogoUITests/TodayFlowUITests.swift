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

    func testЗаписьЕдыПоявляетсяВЛенте() {
        app.buttons["Еда"].firstMatch.tap()
        let записать = app.buttons["Записать"]
        XCTAssertTrue(записать.waitForExistence(timeout: 3))
        записать.tap()
        XCTAssertTrue(app.buttons["Отменить"].waitForExistence(timeout: 3),
                      "каждая запись отменяется тостом")
    }

    func testНастройкиСодержатОбязательныеРазделы() {
        app.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))

        for раздел in ["Данные и приватность", "Политика конфиденциальности", "Условия использования"] {
            let элемент = app.descendants(matching: .any).matching(identifier: раздел).firstMatch
            if !элемент.exists { app.swipeUp() }
            XCTAssertTrue(элемент.waitForExistence(timeout: 3),
                          "\(раздел) — обязательный раздел для App Store")
        }
    }
}
