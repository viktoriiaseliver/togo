import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Togo

/// Кадр пустого состояния — снят, положен файлом и ЗАМЕРЕН.
///
/// **Зачем отдельно от текстового сторожа.** `EmptyStateIllustrationTests`
/// доказывает, что таблица одна и что экран не выбирает картинку.
/// Он не видит, нарисуется ли она: два слоя-шаблона красятся токенами
/// на отрисовке, и «значение верное, а вызов бессильный» у нас оплачено
/// кнопкой с контрастом 1,68:1 — токен был верен всегда, а `foregroundStyle`
/// предка побеждался стилем текста.
///
/// **Почему файлом, а не вложением.** `XCTAttachment` у нас измерен:
/// `xcresulttool export attachments` не выгрузился пять раз из девяти,
/// пакет `.xcresult` остаётся без `Info.plist`. Вложение, которое
/// не выгружается, — это кадр, которого нет. Здесь кадр пишется прямо
/// в дерево, и путь печатается в сообщении проверки: сообщение попадает
/// в лог всегда.
///
/// **И почему замер, а не взгляд.** Глаз соглашается с тем, что привык
/// видеть: кадры той кнопки снимались и раньше, подпись читали глазами
/// и соглашались. Поэтому здесь считаются пиксели, а на кадр я смотрю
/// отдельно — одно не заменяет другого.
@Suite("Кадр пустого состояния: иллюстрация нарисовалась и своим цветом")
@MainActor
struct EmptyStateFrameTests {

    /// Куда ложатся кадры. В дереве, а не в `.xcresult`.
    private static var каталог: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/кадры-пустых-состояний")
    }

    /// Разобранный кадр: ширина, высота и счёт пикселей по цвету.
    private struct Кадр {
        let ширина: Int
        let высота: Int
        let пиксели: [UInt32]  // 0xRRGGBB

        func сколько(близко цель: UInt32, допуск: Int = 10) -> Int {
            пиксели.filter { расстояние($0, цель) <= допуск }.count
        }

        private func расстояние(_ a: UInt32, _ b: UInt32) -> Int {
            let dr = abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
            let dg = abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
            let db = abs(Int(a & 0xFF) - Int(b & 0xFF))
            return max(dr, max(dg, db))
        }
    }

    private func цвет(_ c: Color, _ схема: UIUserInterfaceStyle) -> UInt32 {
        let окружение = UITraitCollection(userInterfaceStyle: схема)
        let тон = UIColor(c).resolvedColor(with: окружение)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        тон.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }

    /// Снять кадр вида и положить файлом. Возвращает путь и разбор.
    private func снять<V: View>(_ вид: V, имя: String,
                                схема: ColorScheme) throws -> (путь: URL, кадр: Кадр) {
        let отрисовщик = ImageRenderer(
            content: вид
                .environment(\.colorScheme, схема)
                .frame(width: 360)
                .background(Color(white: схема == .dark ? 0.04 : 1))
        )
        отрисовщик.scale = 2

        let картинка = try #require(отрисовщик.uiImage, "ImageRenderer не отдал картинку")
        let данные = try #require(картинка.pngData(), "картинка не превратилась в PNG")

        try FileManager.default.createDirectory(at: Self.каталог,
                                                withIntermediateDirectories: true)
        let путь = Self.каталог.appendingPathComponent("\(имя).png")
        try данные.write(to: путь)

        // Разбор в известный формат: читать байты у чужого
        // `cgImage.dataProvider` — значит верить его порядку каналов.
        let cg = try #require(картинка.cgImage)
        let ш = cg.width, в = cg.height
        var байты = [UInt8](repeating: 0, count: ш * в * 4)
        let пространство = CGColorSpace(name: CGColorSpace.sRGB)!
        let контекст = try #require(CGContext(
            data: &байты, width: ш, height: в, bitsPerComponent: 8,
            bytesPerRow: ш * 4, space: пространство,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        контекст.draw(cg, in: CGRect(x: 0, y: 0, width: ш, height: в))

        var пиксели = [UInt32](); пиксели.reserveCapacity(ш * в)
        for i in stride(from: 0, to: байты.count, by: 4) {
            пиксели.append((UInt32(байты[i]) << 16)
                           | (UInt32(байты[i + 1]) << 8)
                           | UInt32(байты[i + 2]))
        }
        return (путь, Кадр(ширина: ш, высота: в, пиксели: пиксели))
    }

    private func карточка(_ предмет: EmptyStateCard.Subject) -> some View {
        EmptyStateCard(subject: предмет,
                       title: "Заголовок",
                       message: "Строка пояснения, которая объясняет, почему пусто.",
                       actionTitle: "Действие",
                       action: {})
    }

    /// Предметы, у которых по таблице стоит иллюстрация.
    private var сИллюстрацией: [(EmptyStateCard.Subject, TGIllustration.Scene)] {
        EmptyStateCard.Subject.allCases.compactMap { предмет in
            if case .illustration(let сцена) = предмет.look { return (предмет, сцена) }
            return nil
        }
    }

    @Test("Снимать было что: иллюстрации стоят не на нуле предметов")
    func былоЧтоСнимать() {
        #expect(сИллюстрацией.count >= 5, """
            предметов с иллюстрацией \(сИллюстрацией.count), а таблица
            заводилась с пятью. Меньше — значит либо таблицу урезали,
            либо `look` перестал отдавать `.illustration`, и замеры ниже
            зелены потому, что им нечего мерить.
            """)
    }

    @Test("Деталь иллюстрации нарисована АКЦЕНТОМ, а не чем попало")
    func детальАкцентом() throws {
        let акцент = цвет(Token.Action.primary, .light)
        var доклад: [String] = []

        for (предмет, сцена) in сИллюстрацией {
            let (путь, кадр) = try снять(карточка(предмет),
                                         имя: "\(предмет.rawValue)-light",
                                         схема: .light)
            let сколько = кадр.сколько(близко: акцент)
            доклад.append("  \(предмет.rawValue) → \(сцена.rawValue): "
                          + "акцентных пикселей \(сколько) · \(путь.lastPathComponent)")

            #expect(сколько > 100, """
                на кадре `\(предмет.rawValue)` акцентных пикселей \(сколько).

                Слой детали не нарисовался или покрашен не акцентом.
                Это ровно тот случай, который текстовый сторож
                не видит: имя упомянуто, а от упоминания ничего
                не происходит.

                Кадр лежит: \(путь.path)
                """)
        }

        // Пути — в сообщение, а не во вложение: сообщение доезжает всегда.
        print("""
            КАДРЫ (светлая тема), акцент \(String(format: "#%06X", акцент)):
            \(доклад.joined(separator: "\n"))
            Каталог: \(Self.каталог.path)
            """)
    }

    @Test("Контур иллюстрации нарисован приглушёнными чернилами")
    func контурЧернилами() throws {
        let контур = цвет(Token.Ink.secondary, .light)
        for (предмет, _) in сИллюстрацией {
            let (путь, кадр) = try снять(карточка(предмет),
                                         имя: "\(предмет.rawValue)-light",
                                         схема: .light)
            let сколько = кадр.сколько(близко: контур)
            #expect(сколько > 100, """
                на кадре `\(предмет.rawValue)` пикселей контура \(сколько)
                (ждём цвет \(String(format: "#%06X", контур))).
                Кадр: \(путь.path)
                """)
        }
    }

    /// Акцент переведён на индиго 07.10.2026 (`8f4d353`). Деталь
    /// иллюстрации обязана поехать за токеном **сама** — в этом и был
    /// смысл двух слоёв-шаблонов вместо запечённого цвета.
    @Test("Смена акцента доезжает до детали без пересборки картинок")
    func акцентДоезжает() throws {
        let акцент = цвет(Token.Action.primary, .light)
        let лайм = цвет(Color(red: 0xD4 / 255, green: 0xF7 / 255, blue: 0x5F / 255), .light)

        let (путь, кадр) = try снять(карточка(.history), имя: "история-light", схема: .light)

        #expect(кадр.сколько(близко: акцент) > 100,
                "деталь не покрашена текущим акцентом. Кадр: \(путь.path)")
        #expect(кадр.сколько(близко: лайм, допуск: 24) == 0, """
            на кадре остался прежний лайм `#D4F75F`.
            Значит цвет где-то запечён, и смена акцента до детали
            не доезжает — а два слоя-шаблона заведены ровно затем,
            чтобы доезжала. Кадр: \(путь.path)
            """)
    }

    @Test("Границы: чего не проверяет набор кадров пустых состояний")
    func границыНазваны() {
        // · Он мерит ЦВЕТ и счёт пикселей, а не рисунок. Что на кадре
        //   собака с предметом, а не клякса, видит только человек —
        //   кадр для этого и лежит файлом.
        // · Он мерит СВЕТЛУЮ тему. Тёмная, Dark HC и Light HC
        //   не сняты: для них нужен свой порог, а порог без замера —
        //   догадка.
        // · Он не ловит, что `Tools/иллюстрации.py` разложил слои
        //   по смыслу: инструмент делит по ЦВЕТУ, и ошейник
        //   контурного цвета уедет в контур. На кадре это видно
        //   глазом, а счётом пикселей — нет.
        // · Он не проверяет вид на устройстве: `ImageRenderer` рисует
        //   вне экрана, и системные эффекты (вибрантность, увеличенный
        //   шрифт) в кадр не попадают.
        #expect(Bool(true))
    }
}
