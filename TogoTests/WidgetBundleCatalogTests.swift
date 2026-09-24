import Testing
import Foundation

/// Каталог строк обязан входить в цель виджета, а не только в приложение.
///
/// **Замер 24.09.2026, архив 216.** В `TogoWidgetsExtension.appex`
/// не было ни одной `.lproj`: каталог лежал в `Togo/Resources/`, а цель
/// виджета собирается из `TogoWidgets` + `TogoShared`. Значит
/// `String(localized:)` в `TodayWidget.swift` и `Text("выход идёт")`
/// в `WalkLiveActivity.swift` читали бандл расширения, где каталога нет,
/// — француз и украинец видели русский на экране блокировки. Плюс 140
/// локализуемых строк в `TogoShared/`, которые компилируются в оба
/// бандла и в бандле виджета оставались русскими.
///
/// Полнота каталога при этом была в порядке, и сторож полноты молчал
/// честно: он смотрит **файл**, а бандлов два. Это то самое последнее
/// звено — «внутри бандла» звучит как конец цепочки и им не является,
/// если бандлов два.
///
/// Починка — переезд каталога в `TogoShared/Resources/`: эта папка
/// синхронизирована в обе цели.
@Suite("Каталог строк доезжает до бандла виджета")
struct WidgetBundleCatalogTests {

    private static let корень = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Каталоги, которым в бандле виджета делать нечего — поимённо
    /// и с причиной.
    ///
    /// Фразы Siri живут в своём каталоге и работают через App Intents
    /// приложения; виджет их не спрашивает. Исключение проверяется
    /// на существование отдельным тестом: исключение, закрывающее то,
    /// чего нет, — лишняя дыра, про которую никто не помнит.
    private static let толькоПриложению = ["Togo/Resources/AppShortcuts.xcstrings"]

    /// Все каталоги строк в дереве, кроме выгрузок для переводчика.
    private func каталоги() -> [String] {
        var найдено: [String] = []
        for место in ["Togo", "TogoShared", "TogoWidgets"] {
            let обход = FileManager.default.enumerator(
                at: Self.корень.appendingPathComponent(место), includingPropertiesForKeys: nil)
            while let элемент = обход?.nextObject() as? URL {
                guard элемент.pathExtension == "xcstrings" else { continue }
                найдено.append(
                    элемент.path.replacingOccurrences(of: Self.корень.path + "/", with: ""))
            }
        }
        return найдено.sorted()
    }

    /// Папки, синхронизированные в цель, — из `project.pbxproj`, а не
    /// из генератора.
    ///
    /// Читаем то, что получает `xcodebuild`, а не то, что задумал
    /// `Tools/generate_project.py`: исходник говорит, что мы задумали.
    /// Разбор — штатным `PropertyListSerialization` (pbxproj это
    /// OpenStep-plist), а не регуляркой: у регулярки по структуре
    /// свои ложные ответы.
    private func папкиЦели(_ имя: String) throws -> [String] {
        let данные = try Data(
            contentsOf: Self.корень.appendingPathComponent("Togo.xcodeproj/project.pbxproj"))
        let разобрано = try PropertyListSerialization.propertyList(
            from: данные, options: [], format: nil) as? [String: Any]
        let объекты = разобрано?["objects"] as? [String: Any] ?? [:]
        for (_, значение) in объекты {
            guard let объект = значение as? [String: Any],
                  объект["isa"] as? String == "PBXNativeTarget",
                  объект["name"] as? String == имя else { continue }
            let группы = объект["fileSystemSynchronizedGroups"] as? [String] ?? []
            return группы.compactMap { (объекты[$0] as? [String: Any])?["path"] as? String }
        }
        return []
    }

    @Test("Каждый каталог строк входит в цель виджета")
    func каталогВЦелиВиджета() throws {
        let все = каталоги()
        // Сканер, переставший что-либо находить, молчит так же, как тот,
        // кому нечего сказать.
        #expect(все.count >= 2, "каталогов найдено \(все.count) — сканер смотрит не туда")

        let папки = try папкиЦели("TogoWidgetsExtension")
        #expect(!папки.isEmpty, """
            у цели TogoWidgetsExtension не нашлось ни одной синхронизированной папки. \
            Либо цель переименовали, либо разбор project.pbxproj сломался — \
            в обоих случаях этот сторож ничего не проверяет.
            """)

        for каталог in все where !Self.толькоПриложению.contains(каталог) {
            let папка = каталог.split(separator: "/").first.map(String.init) ?? каталог
            #expect(папки.contains(папка), """
                каталог \(каталог) не входит в цель виджета: она собирается из \
                \(папки.joined(separator: " + ")). Строки из TogoShared и TogoWidgets \
                в бандле расширения останутся русскими на всех языках — это экран \
                блокировки и «остров», то есть самые заметные поверхности. \
                Переезд в TogoShared/Resources/ или новое исключение с причиной.
                """)
        }

        print("""
            Граница этого сторожа: он читает project.pbxproj, а не собранный бандл. \
            Последнее звено — `.lproj` внутри `.appex`, и его проверяет \
            Tools/check_bundle_languages.sh на шаге `make archive`. \
            «Зелено здесь» значит «цель объявлена верно», а не «языки в бандле есть».
            """)
    }

    @Test("Исключение не закрывает файл, которого нет")
    func исключенияСуществуют() {
        for каталог in Self.толькоПриложению {
            #expect(
                FileManager.default.fileExists(
                    atPath: Self.корень.appendingPathComponent(каталог).path),
                """
                в исключениях записан \(каталог), а файла нет. Исключение, \
                закрывающее то, чего нет, — лишняя дыра: следующий каталог \
                с этим именем пройдёт мимо проверки молча.
                """)
        }
    }
}
