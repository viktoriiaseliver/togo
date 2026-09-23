import SwiftUI
import SwiftData

/// Две собаки с одной кличкой — и что с этим делать.
///
/// Замер 23.09.2026 на живом телефоне: две «Стич», записи разошлись
/// пополам — 56 у одной и 45 у другой. Человек видит две одинаковые
/// карточки и не понимает, которая «настоящая»; половина дня лежит
/// в той, которую он не смотрит.
///
/// Откуда берётся: приложение может открыть хранилище локально, а позже
/// получить право на iCloud — и тогда к локальной собаке приезжает
/// её облачная копия, заведённая раньше. У сборок 80 и 85 право
/// на iCloud как раз чинили, так что случиться это могло у любого.
///
/// Эвристики, по которым сделано именно так:
///
/// - **№1, видимость состояния.** Пока карточки нет, приложение молчит
///   о том, что знает: дубликат виден только человеку и только если он
///   заметит. Карточка называет вещь своим именем.
/// - **№5, предотвращение ошибок.** Очевидное действие — удалить
///   «лишнюю» собаку — уносит её записи каскадом. Поэтому удаления
///   здесь нет вовсе: есть слияние, и оно переносит.
/// - **№9, распознать и исправить.** Сказано, сколько записей переедет
///   и какая карточка останется, — до нажатия, а не после.
struct DuplicateDogCard: View {
    @Environment(\.modelContext) private var context
    @Query private var dogs: [Dog]

    @State private var слито: String?
    @State private var ошибка: String?

    private var дубликаты: [String: [Dog]] {
        Dictionary(grouping: dogs, by: \.name).filter { $0.value.count > 1 }
    }

    var body: some View {
        if let ошибка {
            TGBanner(tone: .alarm, title: "Не получилось",
                     subtitle: .готовая(ошибка), systemImage: "exclamationmark.triangle")
        } else if let слито {
            TGBanner(tone: .done, title: "Собаки слиты",
                     subtitle: .готовая(слито), systemImage: "checkmark.circle")
        } else if let (кличка, группа) = дубликаты.sorted(by: { $0.key < $1.key }).first {
            TGCard {
                TGSectionHeader(title: "одна собака записана дважды")
                TGExplainer(text: .готовая(объяснение(кличка, группа)))
                TGButton(title: "Свести в одну", systemImage: "arrow.triangle.merge") {
                    свести(группа)
                }
            }
        }
    }

    private func объяснение(_ кличка: String, _ группа: [Dog]) -> String {
        let по_дате = группа.sorted { $0.createdAt < $1.createdAt }
        let старшая = по_дате[0]
        let переезжает = по_дате.dropFirst().map(связанных).reduce(0, +)
        let когда = старшая.createdAt.formatted(date: .numeric, time: .shortened)
        let первое = String(localized: "«\(кличка)» в дневнике дважды, и записи разошлись: часть в одной карточке, часть в другой.")
        let второе = String(localized: "Сведу в ту, что заведена \(когда), и перенесу в неё \(переезжает) записей. Ничего не удалится.")
        return первое + " " + второе
    }

    private func свести(_ группа: [Dog]) {
        do { try слить(группа) }
        catch {
            слито = nil
            ошибка = String(localized: "Не вышло свести: \(error.localizedDescription)")
        }
    }

    /// Молчать здесь нельзя: человек нажал «свести», и если не вышло,
    /// он должен это увидеть, а не гадать, почему карточка осталась.
    private func слить(_ группа: [Dog]) throws {
        let по_дате = группа.sorted { $0.createdAt < $1.createdAt }
        guard let главная = по_дате.first else { return }
        var перенесено = 0
        for лишняя in по_дате.dropFirst() {
            перенесено += связанных(лишняя)
            лишняя.eventsStorage?.forEach { $0.dog = главная }
            лишняя.weightsStorage?.forEach { $0.dog = главная }
            лишняя.careTasksStorage?.forEach { $0.dog = главная }
            лишняя.medicationsStorage?.forEach { $0.dog = главная }
            лишняя.trainingStepsStorage?.forEach { $0.dog = главная }
            лишняя.trainingSessionsStorage?.forEach { $0.dog = главная }
            лишняя.tripsStorage?.forEach { $0.dog = главная }
            лишняя.documentsStorage?.forEach { $0.dog = главная }
            лишняя.daysOutStorage?.forEach { $0.dog = главная }
            лишняя.heatsStorage?.forEach { $0.dog = главная }
            лишняя.stocksStorage?.forEach { $0.dog = главная }
            // Связи записываются ДО удаления: иначе каскад заберёт их
            // вместе с карточкой, и человек потеряет половину дневника
            // ровно тем действием, которым хотел его починить.
            try context.save()
            context.delete(лишняя)
        }
        try context.save()
        слито = String(localized: "Перенесено записей: \(перенесено). Дневник снова один.")
        Haptics.success()
    }

    private func связанных(_ собака: Dog) -> Int {
        (собака.eventsStorage?.count ?? 0) + (собака.weightsStorage?.count ?? 0)
            + (собака.careTasksStorage?.count ?? 0) + (собака.medicationsStorage?.count ?? 0)
            + (собака.trainingStepsStorage?.count ?? 0) + (собака.trainingSessionsStorage?.count ?? 0)
            + (собака.tripsStorage?.count ?? 0) + (собака.documentsStorage?.count ?? 0)
            + (собака.daysOutStorage?.count ?? 0) + (собака.heatsStorage?.count ?? 0)
            + (собака.stocksStorage?.count ?? 0)
    }
}
