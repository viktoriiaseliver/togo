import Testing
import Foundation
@testable import Togo

/// Список языков рисуется из бандла и уходит в `ForEach(id: \.self)`.
/// Повтор там — это не косметика: два одинаковых ряда «Русский» человек
/// читает как поломку, а список с одинаковыми идентификаторами ведёт
/// себя неопределённо.
///
/// Так и было до 23.09: `CFBundleLocalizations` в `Togo-Info.plist`
/// называл `ru`, папка `ru.lproj` называла его же, и
/// `Bundle.main.localizations` отдавал `["fr", "ru", "ru"]`.
/// В `СТАТУС.md` это лежало как «несколько русских языков,
/// не воспроизводится по коду» — воспроизвелось на симуляторе.
@Suite("Языки приложения")
struct LocalizationTests {

    @Test("Бандл не называет один язык дважды")
    func безПовторов() {
        let языки = Bundle.main.localizations.filter { $0 != "Base" }
        #expect(Set(языки).count == языки.count,
                "в бандле повторяются языки: \(языки.sorted())")
    }

    @Test("Французский в бандле есть — витрина обещает его на французской странице")
    func французскийНаМесте() {
        #expect(Bundle.main.localizations.contains("fr"))
    }

    @Test("Список для экрана языка идёт без повторов")
    func списокЭкранаБезПовторов() {
        let список = Settings().availableLanguages
        #expect(Set(список).count == список.count, "повторы в списке: \(список)")
        #expect(список.contains("ru"))
    }
}
