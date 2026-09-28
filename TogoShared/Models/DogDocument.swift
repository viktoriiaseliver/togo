import Foundation
import SwiftData

/// Фотография документа: паспорт, чип, результат анализа, назначение.
///
/// Лежит на телефоне рядом с дневником, потому что нужна ровно там же —
/// у врача, на границе и когда собака потерялась. Никуда не отправляется.
@Model
final class DogDocument {
    var id: UUID = UUID()
    var title: String = ""
    /// Снимок лежит рядом с базой, а не внутри неё: страница паспорта
    /// весит куда больше всех записей дневника вместе взятых.
    @Attribute(.externalStorage) var image: Data?
    var addedAt: Date = Date()
    var note: String?

    var dog: Dog?

    init(title: String, image: Data? = nil, note: String? = nil) {
        self.title = title
        self.image = image
        self.note = note
    }
}

/// То, что собака может съесть и от чего бывает плохо.
///
/// Приложение не лечит и не ставит диагнозов — оно только помнит список
/// и говорит, звонить прямо сейчас или наблюдать. Решение всегда за врачом,
/// и это написано на самом экране.
nonisolated struct ToxicItem: Identifiable, Sendable {
    enum Urgency: Sendable {
        case callNow
        case watch

        var title: String {
            switch self {
            case .callNow: String(localized: "Звони врачу сейчас")
            case .watch: String(localized: "Наблюдай и позвони при симптомах")
            }
        }
    }

    var id: String { name }
    var name: String
    var urgency: Urgency
    var detail: String

    /// Список короткий намеренно: длинный никто не дочитает в панике.
    /// Здесь только то, что чаще всего оказывается на полу в квартире.
    static let common: [ToxicItem] = [
        ToxicItem(name: "Ксилит",
                  urgency: .callNow,
                  detail: "Подсластитель в жвачке, конфетах без сахара, некоторых пастах и арахисовой пасте. Опасен даже в малом количестве — резко падает сахар."),
        ToxicItem(name: "Шоколад",
                  urgency: .callNow,
                  detail: "Чем темнее, тем опаснее. Горький и какао-порошок — самые тяжёлые."),
        ToxicItem(name: "Виноград и изюм",
                  urgency: .callNow,
                  detail: "Безопасной дозы не установлено: у части собак отказывают почки от нескольких ягод."),
        ToxicItem(name: "Лекарства человека",
                  urgency: .callNow,
                  detail: "Ибупрофен и парацетамол для собак токсичны. Никогда не давай их сама, даже «половинку»."),
        ToxicItem(name: "Антифриз",
                  urgency: .callNow,
                  detail: "Сладкий на вкус, поэтому собаки его слизывают. Счёт идёт на часы."),
        ToxicItem(name: "Дрожжевое тесто",
                  urgency: .callNow,
                  detail: "Продолжает подниматься в желудке и выделяет спирт."),
        ToxicItem(name: "Лук и чеснок",
                  urgency: .watch,
                  detail: "В любом виде, включая порошок в готовой еде. Разрушают эритроциты, признаки появляются не сразу."),
        ToxicItem(name: "Кости варёные",
                  urgency: .watch,
                  detail: "Колются на острые осколки. Не вызывай рвоту — можно поранить пищевод."),
        ToxicItem(name: "Косточки от фруктов",
                  urgency: .watch,
                  detail: "Персик, слива, авокадо: и содержимое, и риск закупорки."),
        ToxicItem(name: "Солёное, копчёное, жирное",
                  urgency: .watch,
                  detail: "Частая причина панкреатита после праздников."),
    ]
}
