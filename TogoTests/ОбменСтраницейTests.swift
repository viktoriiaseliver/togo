import Testing
import Foundation
import CloudKit
import SwiftData
@testable import Togo

/// Приём чужой страницы — одним сохранением, и честно на отказе.
///
/// **Замер чтением 29.10.2026.** Каждый `SharedDiaryInbox.accept` звал
/// `save()` сам: страница движка в сотни записей — сотни сохранений
/// на главном потоке подряд, каждое со своим `didSave` и перерисовкой
/// всех `@Query`. Экран стоял, пока шла пачка. Сколько именно стоял
/// на живом телефоне — **НЕ ИЗМЕРЕНО**: стенда с двумя iCloud нет.
@Suite("Обмен · страница одним сохранением", .serialized)
@MainActor
struct ОбменСтраницейTests {

    private func клиника(_ id: UUID = UUID(), имя: String = "Vet Riviera",
                         телефон: String? = nil, когда: Date) -> ClinicPayload {
        ClinicPayload(id: id, name: имя, detail: nil, isLab: false,
                      phone: телефон, createdAt: когда, changedAt: когда)
    }

    /// Мерило — `hasChanges` после каждой записи, а не счёт `didSave`:
    /// уведомление ловили бы и соседние наборы, идущие параллельно,
    /// а несохранённое изменение видно только у этого контекста.
    @Test("Страница из трёх записей сохраняется ОДИН раз, в конце")
    func одноСохранение() throws {
        let context = ModelContext(Persistence.container())
        let когда = Date()
        var несохранённоПосле: [Bool] = []

        let записано = SharedDiaryInbox.партией(context: context) {
            for имя in ["Vet Riviera", "Clinique du Port", "Labo Azur"] {
                SharedDiaryInbox.accept(клиника(имя: имя, когда: когда), context: context)
                несохранённоПосле.append(context.hasChanges)
            }
        }

        #expect(несохранённоПосле == [true, true, true], """
            внутри страницы запись сохранилась сама: \(несохранённоПосле). \
            Сохранение на запись — это и есть замерзающий экран \
            на догоняющей странице в сотни записей.
            """)
        #expect(записано)
        #expect(!context.hasChanges, "страница не сохранилась в конце")
        #expect(try context.fetch(FetchDescriptor<Clinic>()).count == 3)
    }

    /// Контроль: вне партии приём пишет сразу, как писал всегда —
    /// его зовут архив и тесты, и ждать конца страницы им не у кого.
    @Test("Вне партии приём записывает сразу")
    func внеПартииСразу() {
        let context = ModelContext(Persistence.container())
        SharedDiaryInbox.accept(клиника(когда: Date()), context: context)
        #expect(!context.hasChanges, "вне партии запись осталась несохранённой")
    }

    /// Честность отказа переехала в конец партии — и не потерялась.
    @Test("Не записалась страница — возвращено всё, что она тронула")
    func откатВсейСтраницы() throws {
        let старая = UUID()
        let давно = Date(timeIntervalSince1970: 1_000_000)
        let context = try НеЗаписывающееХранилище.контекст { пишущий in
            let своя = Clinic(name: "Vet Riviera")
            своя.id = старая
            своя.createdAt = давно
            своя.changedAt = давно
            пишущий.insert(своя)
        }

        let позже = давно.addingTimeInterval(3600)
        let записано = SharedDiaryInbox.партией(context: context) {
            // Слияние: чужая правка позже — телефон бы переписался.
            SharedDiaryInbox.accept(клиника(старая, телефон: "+33 4 93 00 00 00", когда: позже),
                                    context: context)
            // И вставка новой.
            SharedDiaryInbox.accept(клиника(имя: "Labo Azur", когда: позже), context: context)
        }

        #expect(записано == false, "запертое хранилище обязано ответить «нет»")
        let клиники = try context.fetch(FetchDescriptor<Clinic>())
        #expect(клиники.count == 1, """
            вставка из несохранившейся страницы осталась в контексте: \
            \(клиники.map(\.name)). Экран показал бы запись, которой \
            в хранилище нет.
            """)

        // Предмет берётся ПО ID, а не `.first`: у `fetch` без `sortBy`
        // порядка нет, и когда откат вставки отказывал, `.first`
        // отдавал «Labo Azur» — запись с чужими полями. Два ожидания
        // про слияние читали тогда НЕ ТУ клинику и отвечали про неё:
        // `phone == nil` проходило (у вставки телефона и не было),
        // `changedAt` падало. Один дефект выглядел тремя, и ни одно
        // из трёх сообщений не называло его.
        let своя = клиники.first { $0.id == старая }
        #expect(своя != nil, "своя клиника пропала из контекста целиком")
        #expect(своя?.phone == nil, "слияние из несохранившейся страницы не возвращено")
        #expect(своя?.changedAt == давно, """
            `changedAt` остался чужим: \(своя?.changedAt.description ?? "—") \
            при \(давно). Возврат слияния — `local.apply(былПрежний)`.
            """)
    }
}

/// iCloud просит подождать — это не «нет сети» и не поломка.
@Suite("Обмен · просьба iCloud подождать")
@MainActor
struct ПросьбаПодождатьTests {

    private func отказ(_ код: CKError.Code, через секунд: Double? = nil) -> Error {
        var сведения: [String: Any] = [:]
        if let секунд { сведения[CKErrorRetryAfterKey] = NSNumber(value: секунд) }
        return NSError(domain: CKErrorDomain, code: код.rawValue, userInfo: сведения)
    }

    @Test("Три кода — просьба подождать, со сроком из самого отказа")
    func коды() {
        #expect(FamilySync.просьбаПодождать([отказ(.requestRateLimited, через: 90)]) == 90)
        #expect(FamilySync.просьбаПодождать([отказ(.zoneBusy, через: 5)]) == 5)
        #expect(FamilySync.просьбаПодождать([отказ(.serviceUnavailable)]) == 0,
                "просьба без срока — ноль, а не выдуманный срок")
    }

    @Test("Обрыв сети и чужой отказ — не просьба подождать")
    func неПросьба() {
        #expect(FamilySync.просьбаПодождать([отказ(.networkFailure)]) == nil)
        #expect(FamilySync.просьбаПодождать([NSError(domain: "мой.домен", code: 7)]) == nil)
        #expect(FamilySync.просьбаПодождать([]) == nil)
    }

    /// `fetchChanges` отдаёт составной отказ, а срок лежит по записям.
    @Test("Из составного отказа берётся больший срок")
    func составной() {
        let составной = NSError(
            domain: CKErrorDomain, code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [
                "а": отказ(.zoneBusy, через: 30),
                "б": отказ(.requestRateLimited, через: 300),
                "в": отказ(.unknownItem),
            ] as [AnyHashable: Error]])
        #expect(FamilySync.просьбаПодождать([составной]) == 300, """
            раньше большего срока не пустят никого — меньший обещал бы \
            человеку повтор, который снова упрётся в ту же просьбу
            """)
    }

    @Test("Человек читает «подождать», а не английский текст CloudKit")
    func текст() {
        guard case .failed(let текст) = FamilySync.состояние(
            послеОтказов: [отказ(.requestRateLimited, через: 90)], lastSync: nil) else {
            Issue.record("просьба подождать не стала видимым состоянием")
            return
        }
        #expect(текст.contains("подождать"), "«\(текст)»")
        #expect(текст.contains("2"), "90 секунд — это «через 2 мин», вверх: «\(текст)»")
    }

    @Test("Минуты — вверх и не меньше одной")
    func минуты() {
        #expect(FamilySync.текстПаузы(секунд: 1).contains("1"))
        #expect(FamilySync.текстПаузы(секунд: 61).contains("2"))
        #expect(FamilySync.текстПаузы(секунд: 0) != FamilySync.текстПаузы(секунд: 60),
                "«срока не назвали» и «одна минута» — разные ответы")
    }
}
