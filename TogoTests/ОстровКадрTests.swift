import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Togo

/// Кадры «острова» и экрана блокировки — в ОБЕИХ темах.
///
/// **Заведено 07.10.2026, `togo-1e`, по одной причине: этой поверхности
/// не видел никто.** `UIUserInterfaceStyle = Dark` стоял в `Info.plist`
/// (снят в `052c562`) и гасил светлую тему вовсе, поэтому все сегодняшние
/// кадры — медкнижка, плакат, французские экраны — сняты в тёмной.
/// Как приёмка расстановки и слов они целы; как приёмка цвета
/// не существуют.
///
/// У нас записано: **поверхность, которую нельзя снять кадром, никто
/// не проверял**, и Live Activity у Togo и Timer была ровно такой —
/// самой важной и единственной непроверяемой. Починено входом: вид
/// принимает обычные структуры, а не `ActivityViewContext`, и потому
/// попадает в отрисовку.
///
/// ## Чего этот кадр НЕ доказывает
///
/// `.activityBackgroundTint(Token.Surface.card)` — это **просьба**,
/// а не результат: поверх неё система рисует «остров» вибрантным
/// монохромом по-своему, и предсказать итог автор токенов не берётся.
///
/// > **Кадр здесь не подтверждает число, а показывает результат.**
/// > Если выйдет нечитаемо — это решение дизайна, а не дефект,
/// > и докладывать надо так.
///
/// То есть на этих кадрах видно, что отдаёт ПРИЛОЖЕНИЕ. Что покажет
/// система на живом телефоне, кадром из отрисовщика не измеряется
/// вовсе — и это названо здесь, а не оставлено читателю.
@Suite("Кадры острова в обеих темах")
struct ОстровКадрTests {

    /// Куда ложатся кадры — в дерево, а не в `.xcresult`: кадр
    /// существует, когда он снят И на него посмотрели, а в бандле
    /// на него не смотрит никто.
    private static var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/кадры-острова")
    }

    /// Снять кадр вида в названной теме.
    ///
    /// Приём взят у `EmptyStateFrameTests` НЕ из экономии: третья
    /// реализация сломается так же, как первые две, и у нас это
    /// записано ценой дня. Суть — отрисовка **внутри** нужной
    /// `UITraitCollection`: токены это динамические `UIColor`,
    /// и разрешаются они по `UITraitCollection.current`, а не
    /// по окружению SwiftUI. Тест, просящий светлую через
    /// `.environment`, напечатал бы «светлая» и отрисовал тёмное.
    private func снять<V: View>(_ вид: V, имя: String,
                                схема: ColorScheme) throws -> URL {
        let стиль: UIUserInterfaceStyle = схема == .dark ? .dark : .light
        var нарисованное: UIImage?
        UITraitCollection(userInterfaceStyle: стиль).performAsCurrent {
            let отрисовщик = ImageRenderer(
                content: вид
                    .environment(\.colorScheme, схема)
                    .frame(width: 360)
                    // Фон — то, что ПРОСИТ приложение у «острова»:
                    // `.activityBackgroundTint(Token.Surface.card)`.
                    // Система поверх него рисует своё, и кадр об этом
                    // не знает.
                    .background(Token.Surface.card)
            )
            отрисовщик.scale = 2
            нарисованное = отрисовщик.uiImage
        }
        let картинка = try #require(нарисованное, "ImageRenderer не отдал картинку")
        let данные = try #require(картинка.pngData(), "картинка не стала PNG")
        try FileManager.default.createDirectory(at: Self.каталог,
                                                withIntermediateDirectories: true)
        let путь = Self.каталог.appendingPathComponent("\(имя).png")
        try данные.write(to: путь)
        return путь
    }

    /// Первым — проверка, что отрисовщику было что рисовать.
    ///
    /// Пустая картинка весит мало и выглядит как кадр. Без этой
    /// проверки остальные три молчали бы так же, как при всём хорошем.
    @Test("Отрисовщику было что рисовать")
    func былоЧтоРисовать() throws {
        let путь = try снять(
            WalkActivityView(dogName: "Стич", startedBy: "Виктория",
                             startedAt: Date().addingTimeInterval(-18 * 60),
                             tally: nil),
            имя: "контроль", схема: .dark)
        let вес = try FileManager.default.attributesOfItem(atPath: путь.path)[.size] as? Int ?? 0
        #expect(вес > 3000, "кадр весит \(вес) байт — для карточки с текстом это пустая картинка")
    }

    @Test("Карточка экрана блокировки — светлая и тёмная")
    func карточка() throws {
        for (схема, имя) in [(ColorScheme.dark, "остров-карточка-тёмная"),
                             (ColorScheme.light, "остров-карточка-светлая")] {
            let путь = try снять(
                WalkActivityView(dogName: "Стич", startedBy: "Виктория",
                                 startedAt: Date().addingTimeInterval(-18 * 60),
                                 tally: "пописал 1"),
                имя: имя, схема: схема)
            #expect(FileManager.default.fileExists(atPath: путь.path))
        }
    }

    @Test("Компактные части «острова» — светлая и тёмная")
    func компактные() throws {
        for (схема, суффикс) in [(ColorScheme.dark, "тёмная"),
                                 (ColorScheme.light, "светлая")] {
            // Контейнер — `WalkIslandView`, НЕ `WalkActivityView`: три
            // области «острова» объявлены отдельным перечислением
            // (`WalkActivityView.swift:132`), потому что
            // `DynamicIslandExpandedRegion` принимает содержимое
            // по одной области и собрать их в один вид нельзя.
            //
            // Первая редакция звала `WalkActivityView.Leading`, и сборка
            // отвечала `type 'WalkActivityView' has no member 'Leading'`.
            // Отказ назвал сторону, которая отказала, и не назвал причину:
            // читается как «члена нет» — а член есть, тремя строками ниже
            // в соседнем контейнере, с той же подписью до аргумента.
            _ = try снять(WalkIslandView.Leading(dogName: "Стич"),
                          имя: "остров-ведущая-\(суффикс)", схема: схема)
            _ = try снять(WalkIslandView.Trailing(startedAt: Date().addingTimeInterval(-18 * 60)),
                          имя: "остров-ведомая-\(суффикс)", схема: схема)
            _ = try снять(WalkIslandView.Bottom(startedBy: "Виктория",
                                                dogName: "Стич",
                                                tally: "пописал 1"),
                          имя: "остров-низ-\(суффикс)", схема: схема)
        }
        #expect(Bool(true), "кадры сняты; смотреть на них — отдельное действие")
    }
}
