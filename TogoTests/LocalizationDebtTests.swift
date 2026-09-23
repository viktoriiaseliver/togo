import Testing
import Foundation

/// Русская строка в общем слое — либо подпись, которую забыли перевести,
/// либо внутреннее, которое переводить нельзя. Граница между ними до
/// 23.09 держалась на памяти, а по ту сторону 443 литерала.
///
/// Сторож её закрепляет: у каждого исключения написана причина, а всё
/// остальное — долг, который не должен расти. Долг снимается переводом
/// через `String(localized:)`, а не правкой числа.
///
/// Чего сторож НЕ умеет: отличить подпись от внутренней строки внутри
/// одного файла. Поэтому исключения — по файлам, и список короткий
/// намеренно: длинный список исключений — это сторож, который не может
/// покраснеть.
@Suite("Долг локализации")
struct LocalizationDebtTests {

    /// Файлы, где русский текст — не подпись и переводу не подлежит.
    /// У каждого причина, и она важнее самого списка.
    private let исключения: [String: String] = [
        // Ключевые слова разбора дозаписи: человек пишет «был понос»,
        // парсер ищет «понос». Перевод сломает разбор для пишущих
        // по-русски. Украинцу нужен свой словарь, а не перевод этого.
        "RecallParser.swift": "слова разбора, а не подписи",
        // Тот же случай: словарь разбора по языкам. Слова здесь ищутся
        // в напечатанной фразе, а не показываются человеку.
        "RecallDictionary.swift": "слова разбора, а не подписи",
        // Журнал действий и отчёт по нему читает разработчик, не хозяин.
        // Диагностика, ставшая текстом для человека, — это дефект.
        "UsageLog.swift": "внутренний журнал",
        "UsageReport.swift": "внутренний журнал",
        // Крошки запуска: их забирают с телефона скриптом, когда
        // приложение не поднялось.
        "Persistence.swift": "крошки запуска",
        "StartupLog.swift": "крошки запуска",
        // Откуда взялась собака — тоже крошки: пишутся в тот же файл
        // и читаются тем, кто ищет причину дубликата, а не хозяином.
        "DogOrigin.swift": "крошки запуска",
    ]

    /// Сколько непереведённых строк осталось в каждом файле.
    /// Замер 23.09.2026. Число может только уменьшаться.
    private let долг: [String: Int] = [
        "ActiveSession.swift": 1, "AlarmThreshold.swift": 5, "Backup.swift": 6,
        "Care.swift": 15, "CareMigration.swift": 14, "DayOutPlan.swift": 5,
        "Dog.swift": 3, "DogDocument.swift": 22, "DoseGate.swift": 2,
        "Enums+Care.swift": 3, "FamilyShare.swift": 4, "FamilySync.swift": 3,
        "Feeding.swift": 5, "FoodStock.swift": 9, "Formatting.swift": 12,
        "LogEvent.swift": 3, "NeedVerdict.swift": 29, "PillSupply.swift": 2,
        "RecallWriter.swift": 1, "RecordOrigin.swift": 4, "ScheduleChange.swift": 9,
        "Shift.swift": 4, "TimelineBuilder.swift": 9, "Training.swift": 2,
        "TreatmentCourse.swift": 10, "VetSummary.swift": 10, "WalkMarkIntent.swift": 8,
        "WalkRecorder.swift": 1, "WidgetSnapshot.swift": 3,
    ]

    @Test("Непереведённых строк в общем слое не становится больше")
    func долгНеРастёт() throws {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TogoShared")

        var посчитано: [String: Int] = [:]
        let обход = FileManager.default.enumerator(at: корень, includingPropertiesForKeys: nil)
        while let элемент = обход?.nextObject() as? URL {
            guard элемент.pathExtension == "swift",
                  let текст = try? String(contentsOf: элемент, encoding: .utf8) else { continue }
            let имя = элемент.lastPathComponent
            guard исключения[имя] == nil else { continue }
            var n = 0
            for строка in текст.components(separatedBy: .newlines) {
                let код = строка.components(separatedBy: "//")[0]
                // Строка в журнал разработчика — не подпись. Её читает тот,
                // кто чинит, а не хозяин собаки; переводить её значит
                // превращать диагностику в текст для человека.
                // Тот же признак, что и у Tools/extract_texts.py.
                if код.contains("log.error(") || код.contains("log.notice(")
                    || код.contains("log.debug(") || код.contains("log.info(")
                    || код.contains("log.warning(") { continue }
                n += Self.русскиеЛитералы(в: код)
            }
            if n > 0 { посчитано[имя] = n }
        }

        for (файл, сколько) in посчитано.sorted(by: { $0.key < $1.key }) {
            let разрешено = долг[файл] ?? 0
            #expect(сколько <= разрешено, """
                \(файл): непереведённых строк \(сколько) при долге \(разрешено). \
                Либо переведи через String(localized:), либо, если это \
                внутреннее, добавь файл в исключения — с причиной, а не молча. \
                Правку числа в долге считать починкой нельзя.
                """)
        }

        // Долг, которого больше нет, надо убирать из списка: иначе он
        // разрешает вернуть то, что уже починено.
        let протухшие = долг.keys.filter { посчитано[$0] == nil }.sorted()
        #expect(протухшие.isEmpty,
                "в долге числятся файлы без непереведённых строк: \(протухшие). Убери их.")
    }

    @Test("У каждого исключения есть причина и оно существует")
    func исключенияЧестные() {
        let корень = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TogoShared")
        for (файл, причина) in исключения {
            #expect(!причина.isEmpty, "\(файл): исключение без причины")
            let есть = FileManager.default.enumerator(at: корень, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .contains { $0.lastPathComponent == файл } ?? false
            #expect(есть, "\(файл) в исключениях, а файла нет — список протух")
        }
        #expect(исключения.count <= 8,
                "исключений \(исключения.count): длинный список — это сторож, который не может покраснеть")
    }

    /// Русские литералы в строке кода, кроме уже обёрнутых в перевод.
    private static func русскиеЛитералы(в код: String) -> Int {
        var счёт = 0
        var внутри = false
        var литерал = ""
        var предыдущий: Character = " "
        var началоЛитерала = код.startIndex
        var i = код.startIndex
        while i < код.endIndex {
            let c = код[i]
            if внутри {
                if c == "\"" && предыдущий != "\\" {
                    внутри = false
                    if литерал.contains(where: { $0.isCyrillic }) {
                        let перед = код[код.startIndex..<началоЛитерала]
                            .trimmingCharacters(in: .whitespaces)
                        if !перед.hasSuffix("localized:") { счёт += 1 }
                    }
                    литерал = ""
                } else {
                    литерал.append(c)
                }
            } else if c == "\"" {
                внутри = true
                началоЛитерала = i
            }
            предыдущий = c
            i = код.index(after: i)
        }
        return счёт
    }
}

private extension Character {
    var isCyrillic: Bool {
        guard let скаляр = unicodeScalars.first else { return false }
        return (0x0410...0x044F).contains(Int(скаляр.value)) || скаляр.value == 0x0401 || скаляр.value == 0x0451
    }
}
