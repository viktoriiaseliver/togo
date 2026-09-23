import XCTest
import Foundation

/// Подписи интерфейса для прогона на любом языке.
///
/// Тест водит приложение по надписям, и все они были русскими: французский
/// прогон падал бы на первом же нажатии. Вторую копию подписей в тесте
/// заводить нельзя — разойдётся с приложением молча, и кадр уедет в витрину
/// с чужим словом. Поэтому перевод берётся из того же каталога, который
/// собирается в бандл: `Togo/Resources/Localizable.xcstrings`.
///
/// Путь к каталогу считается от исходника теста (`#filePath`), а не от
/// бандла раннера: класть копию каталога в `TogoUITests/` значило бы
/// то же самое, от чего ушли.
nonisolated struct Подписи {

    /// Язык прогона: `ru`, `fr`. Берётся из языка самого раннера —
    /// `xcodebuild -testLanguage fr` ставит его и приложению, и тесту,
    /// так что расхождения между тем, что нажимает тест, и тем, что
    /// показывает приложение, быть не может.
    let язык: String

    private let переводы: [String: String]

    init(язык: String? = nil) {
        let выбранный = язык ?? String(Locale.preferredLanguages.first?.prefix(2) ?? "ru")
        self.язык = выбранный

        let url = URL(fileURLWithPath: #filePath)     // TogoUITests/Подписи.swift
            .deletingLastPathComponent()              // TogoUITests
            .deletingLastPathComponent()              // корень репозитория
            .appendingPathComponent("Togo/Resources/Localizable.xcstrings")

        guard выбранный != "ru",
              let data = try? Data(contentsOf: url),
              let каталог = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let строки = каталог["strings"] as? [String: Any]
        else {
            переводы = [:]
            return
        }

        var собрано: [String: String] = [:]
        for (ключ, значение) in строки {
            guard let значение = значение as? [String: Any],
                  let локализации = значение["localizations"] as? [String: Any],
                  let язык = локализации[выбранный] as? [String: Any],
                  let единица = язык["stringUnit"] as? [String: Any],
                  let текст = единица["value"] as? String
            else { continue }
            собрано[ключ] = текст
        }
        переводы = собрано
    }

    /// Подпись на языке прогона. Ключ — русская строка, ровно как в коде
    /// приложения.
    ///
    /// Нет перевода — тест падает с именем ключа, а не подставляет русское
    /// молча: молчаливая подстановка и есть тот дефект, ради которого
    /// французские кадры вообще снимаются.
    func callAsFunction(_ русская: String,
                        файл: StaticString = #filePath,
                        строка: UInt = #line) -> String {
        if язык == "ru" { return русская }
        guard let перевод = переводы[русская] else {
            XCTFail("нет перевода на «\(язык)» для «\(русская)» — "
                    + "кадр показал бы русскую надпись на чужой витрине",
                    file: файл, line: строка)
            return русская
        }
        return перевод
    }

    /// То же, но для надписей, которые интерфейс показывает прописными.
    /// Регистр меняет язык прогона, а не `en_US`: в турецком и литовском
    /// это разные буквы.
    func прописными(_ русская: String,
                    файл: StaticString = #filePath,
                    строка: UInt = #line) -> String {
        callAsFunction(русская, файл: файл, строка: строка)
            .uppercased(with: Locale(identifier: язык))
    }
}
