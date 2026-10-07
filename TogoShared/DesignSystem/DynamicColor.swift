import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Цвет, который выбирает СИСТЕМА: тема × повышенный контраст.
///
/// **Почему не Asset Catalog, хотя `SwiftUI.md` хендоффа велит его.**
/// Отход назван вслух и с ценой — он записан в `DECISIONS.md`, чтобы
/// следующий не «вернул единообразие» по хендоффу. Довод один, и он
/// про приёмку:
///
/// > Динамический цвет разрешается в тесте против четырёх
/// > `UITraitCollection` — и это **тот же объект, который возьмёт
/// > экран**. Ассет пришлось бы мерить через бандл тест-таргета.
///
/// У нас дважды оплачено «каталог полон, а на экране не то»: полнота
/// каталога локализации при наполовину русском французском экране
/// и ключ в каталоге при русском слове на французском «острове».
/// Третий раз в том же месте платить не за что.
///
/// Два следствия помельче: значения остаются в git и дифуются (ассет —
/// это 62 каталога по четыре JSON, их диф человек не читает), и места
/// вызова не меняются — `Token.Ink.primary` остаётся `Color`, то есть
/// ни одной правки на тридцати двух поверхностях показа.
///
/// **Чего этот тип НЕ обещает, и это граница, а не задача.** Трейты
/// приходят от того, кто рисует. Приложение их несёт; виджет получает
/// свои от системы; карточка Live Activity и «остров» рисуются
/// системным вибрантным монохромом, и тема там не наша. То есть
/// «светлая тема доехала до Swift» — утверждение про приложение,
/// а не про все пять поверхностей, и проверять их надо кадром каждую.
nonisolated struct Dyn: Sendable, Equatable {
    let dark: UInt32
    let light: UInt32
    let darkHC: UInt32
    let lightHC: UInt32

    init(dark: UInt32, light: UInt32, darkHC: UInt32, lightHC: UInt32) {
        self.dark = dark
        self.light = light
        self.darkHC = darkHC
        self.lightHC = lightHC
    }

    /// Значение для пары «тема × контраст».
    ///
    /// Четыре ветки вместо «тёмная, иначе светлая» нарочно: у восьми
    /// токенов `darkHC` равен нашей тёмной не потому, что контраст
    /// ничего не меняет, а потому что наше тёмное значение расходится
    /// с пакетом и брать его HC значило бы смешать поколения. Это
    /// записано у каждого такого токена в `tokens.json`, и ветка
    /// существует, чтобы такой откат был виден, а не выведен.
    func hex(dark темная: Bool, highContrast контраст: Bool) -> UInt32 {
        switch (темная, контраст) {
        case (true, false): dark
        case (true, true): darkHC
        case (false, false): light
        case (false, true): lightHC
        }
    }

    #if canImport(UIKit)
    /// Динамический `UIColor`: систему спрашивают в момент отрисовки,
    /// а не в момент сборки токенов.
    var uiColor: UIColor {
        UIColor { трейты in
            UIColor(Color(hex: hex(dark: трейты.userInterfaceStyle == .dark,
                                   highContrast: трейты.accessibilityContrast == .high)))
        }
    }
    #endif
}

nonisolated extension Color {
    /// Единственный способ собрать цвет из режимов.
    init(_ dyn: Dyn) {
        #if canImport(UIKit)
        self.init(uiColor: dyn.uiColor)
        #else
        self.init(hex: dyn.dark)
        #endif
    }
}

#if canImport(UIKit)
nonisolated extension Color {
    /// Разрешить цвет так, как его разрешит система, и вернуть `0xRRGGBBAA`.
    ///
    /// **Это вход для приёмки, и он нужен именно у `Color`, а не у `Dyn`.**
    /// Сторож, спрашивающий `Dyn`, мерил бы наши четыре числа — то есть
    /// себя. Спрашивая `Token.Ink.primary`, он мерит то, что отдаст
    /// система тому, кто рисует: у нас записано, что проверять одну
    /// реализацию наблюдениями за другой нельзя.
    func resolvedHex(dark темная: Bool, highContrast контраст: Bool) -> UInt32 {
        let трейты = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: темная ? .dark : .light),
            UITraitCollection(accessibilityContrast: контраст ? .high : .normal),
        ])
        let разрешённый = UIColor(self).resolvedColor(with: трейты)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        разрешённый.getRed(&r, green: &g, blue: &b, alpha: &a)
        func байт(_ x: CGFloat) -> UInt32 { UInt32((x * 255).rounded()) }
        return (байт(r) << 24) | (байт(g) << 16) | (байт(b) << 8) | байт(a)
    }
}
#endif
