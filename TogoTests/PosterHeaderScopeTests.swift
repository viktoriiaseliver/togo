import Testing
import Foundation

/// Шапка-плакат стоит на экранах и **ни на одной шторке**.
///
/// Решение дизайна кончается запретом: «Шторки и системные поверхности
/// без плаката». Запрет и проверяется — **от обратного**, а не счётом
/// «сколько экранов получили шапку». Счёт выполняется и тогда, когда
/// шапку надели лишним местам: «применили везде» истинно и там, где
/// применять нельзя.
///
/// **Этот сторож не теоретический.** Раскатывая шапку на тридцать
/// восемь экранов, я пропустил ровно одну шторку — `WhatsNewScreen`, —
/// и пропустил по глупой причине: список исключений держал НОМЕР
/// СТРОКИ, а номера уехали от предыдущих вставок в том же файле.
/// Поймал этот счёт, а не чтение.
///
/// > Устаревший номер строки — третий случай за день. Адресовать
/// > место текстом, а не координатой: текст стареет громко, номер
/// > молча.
@Suite("Плакат — на экранах, и ни на одной шторке")
struct PosterHeaderScopeTests {

    /// В день написания: 39 экранов с шапкой.
    private static let экрановНеМенее = 35

    private func исходники() -> [(имя: String, путь: String, текст: String)] {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        var найдено: [(String, String, String)] = []
        for цель in ["Togo", "TogoShared", "TogoWidgets"] {
            let обход = FileManager.default.enumerator(
                at: корень.appendingPathComponent(цель), includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "swift",
                      let текст = try? String(contentsOf: элемент, encoding: .utf8)
                else { continue }
                найдено.append((элемент.lastPathComponent,
                                "\(цель)/\(элемент.lastPathComponent)", текст))
            }
        }
        return найдено
    }

    /// Какие виды показываются шторкой. Выводится из дерева, а не
    /// перечисляется: список руками знает только то, что в него
    /// положили, и `WhatsNewScreen` в него бы не попал — его
    /// показывают шторкой из `TogoApp`, а правят в `DataPrivacyScreen`.
    private func шторками() -> Set<String> {
        var имена: Set<String> = []
        for файл in исходники() {
            let строки = файл.текст.components(separatedBy: .newlines)
            for (i, строка) in строки.enumerated() {
                let код = строка.components(separatedBy: "//")[0]
                guard код.contains(".sheet(") || код.contains(".fullScreenCover(")
                else { continue }
                let окно = строки[i..<min(i + 8, строки.count)].joined(separator: "\n")
                for кусок in окно.components(separatedBy: CharacterSet(charactersIn: " (){}[]\n\t,")) {
                    if let первая = кусок.first, первая.isUppercase, кусок.count > 3 {
                        имена.insert(кусок)
                    }
                }
            }
        }
        return имена
    }

    @Test("Обход нашёл экраны с шапкой, а не промолчал")
    func былоЧтоПроверять() {
        let сШапкой = исходники().filter { $0.текст.contains(".posterHeader(") }
        #expect(сШапкой.count >= 20, """
            файлов с шапкой \(сШапкой.count) — обход не состоялся
            или раскатку откатили.
            """)
        let всего = сШапкой.reduce(0) { сумма, файл in
            сумма + файл.текст.components(separatedBy: ".posterHeader(").count - 1
        }
        #expect(всего >= Self.экрановНеМенее, """
            вызовов шапки \(всего), а раскатано было \(Self.экрановНеМенее)+.
            Стало меньше — шапку с экранов сняли.
            """)
    }

    @Test("Ни одна шторка не несёт шапку-плакат")
    func шторкиБезПлаката() {
        let шторки = шторками()
        var нарушения: [String] = []

        for файл in исходники() {
            let строки = файл.текст.components(separatedBy: .newlines)
            var текущий: String?
            for (i, строка) in строки.enumerated() {
                if let m = строка.range(of: #"(?:private )?struct (\w+)"#,
                                        options: .regularExpression) {
                    текущий = String(строка[m]).components(separatedBy: " ").last
                }
                guard строка.components(separatedBy: "//")[0].contains(".posterHeader(")
                else { continue }
                if let текущий, шторки.contains(текущий) {
                    нарушения.append("  \(файл.путь):\(i + 1) — \(текущий) показывается шторкой")
                }
            }
        }

        #expect(нарушения.isEmpty, """
            плакат надет на шторку:

            \(нарушения.joined(separator: "\n"))

            Решение дизайна: «Шторки и системные поверхности без
            плаката». Если вид показывают и шторкой, и переходом —
            разводить явным параметром на месте показа, а не вешать
            шапку на вид.
            """)
    }

    @Test("Границы: чего не проверяет сторож области плаката")
    func границыНазваны() {
        // · Он сверяет ИМЕНА типов, а не показ. Вид, который показывают
        //   шторкой через промежуточную обёртку с другим именем,
        //   он не свяжет.
        // · Он не видит, как шапка ВЫГЛЯДИТ: это текст. Что заголовок
        //   не задвоился и что подложка цветная — только кадр живого
        //   экрана (`TogoUITests/ШапкаПлаката`), и компонентный кадр
        //   здесь слеп по устройству: `ImageRenderer` системную панель
        //   не рисует.
        // · Он не проверяет, что шапка есть у КАЖДОГО экрана: это
        //   требование от утверждения, а они у нас проверяются
        //   ненадёжно. Проверяется запрет и общее число.
        #expect(Bool(true))
    }
}
