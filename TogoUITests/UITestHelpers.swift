import XCTest

/// Общий поиск по началу подписи с прокруткой.
///
/// Подписи в приложении составные («Профиль собаки, Стич»), поэтому точное
/// совпадение по идентификатору не годится, а копия этого метода жила
/// в трёх тестовых классах.
nonisolated extension XCTestCase {
    func найти(_ подпись: String, в app: XCUIApplication, попыток: Int = 6) -> XCUIElement {
        for попытка in 0..<попыток {
            let элемент = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", подпись))
                .firstMatch
            if элемент.exists && элемент.isHittable && !подХромой(элемент, в: app) {
                return элемент
            }
            // Направление прокрутки зависит от того, ПОЧЕМУ элемент
            // не взят. Не дошли — крутить вверх; заехал под хрому —
            // крутить обратно, иначе каждая попытка уводит его глубже.
            if попытка < попыток - 1 {
                if элемент.exists && подХромой(элемент, в: app) {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
        }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", подпись))
            .firstMatch
    }

    /// Элемент заехал под верхнюю хрому навигации.
    ///
    /// **`isHittable` отвечает про видимость, а не про достижимость
    /// тапом, и здесь он лжёт** — замер 21.10.2026 по дереву элементов
    /// из `.xcresult` упавшего прогона:
    ///
    /// ```
    /// кнопка «Записать корм»   {{34, 121.7}, {334, 44}}   isHittable = true
    /// поверх неё               Other {{0,0},{402,170.8}}, Image
    ///                          'AdditionalDimmingOverlay' — в AX-дереве
    ///                          ПОСЛЕ ScrollView, то есть выше по z
    /// исход тапа               XCUITest бьёт в {201.0, 143.7},
    ///                          NavigationLink НЕ выстреливает
    /// ```
    ///
    /// Три теста `FoodStockUITests` падали на этом так, что экран
    /// `FoodStockScreen` не рисовался ни разу (в 1915 объектах бандла
    /// «Чем кормим» — ноль при живых контролях), а отказ приезжал
    /// строками ниже и читался как «нет кнопки „Добавить корм"».
    ///
    /// > Тап в элемент, накрытый хромой, — это не «не нашли»
    /// > и не «нажали»: это третье состояние, и без него оно
    /// > неотличимо от второго.
    private func подХромой(_ элемент: XCUIElement, в app: XCUIApplication) -> Bool {
        let хрома = app.navigationBars.firstMatch
        guard хрома.exists, элемент.exists else { return false }
        return элемент.frame.minY < хрома.frame.maxY
    }
}
