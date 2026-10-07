#if DEBUG
import Foundation
import SwiftData

/// Слияние задвоившихся собак и участников.
///
/// Замер 23.09.2026 на живом телефоне: две собаки с одной кличкой
/// «Стич» — одна заведена 03.09 (56 записей, 10 дел ухода, 1 препарат),
/// вторая 22.09 (45 записей, 8 дел ухода). И четыре участника вместо
/// двух: «Я» и «Мама» дважды. Прогрев зеркала ни при чём — вторая
/// собака заведена накануне.
///
/// Почему это опасно чинить руками: у собаки одиннадцать связей
/// с правилом `.cascade`. Удалить «лишнюю» — значит унести её записи,
/// взвешивания, уход, препараты, занятия, поездки и документы.
/// Поэтому здесь не удаление, а перенос: всё перевешивается на самую
/// раннюю собаку, и только потом пустая убирается.
///
/// Отладочное и временное. Настоящая починка — не дать дубликату
/// появиться; она требует понять, откуда он взялся, и это отдельная
/// работа.
nonisolated enum DuplicateMerge {

    /// Группировка по кличке — **только по настоящей**.
    ///
    /// `Dog.name` и `FamilyMember.name` по умолчанию `""`. Группировка
    /// по такому полю собирает в одну группу всё, что его не заполнило,
    /// и инструмент, созданный переносить записи, предложил бы свести
    /// восемь безымянных фантомов в один — а если среди них окажется
    /// настоящая собака с затёртой кличкой, перенёс бы её дневник
    /// на фантом и убрал её запись.
    ///
    /// Своя дока этого файла говорит «здесь не удаление, а перенос» —
    /// осторожность верная и обходилась с другой стороны: выбор
    /// «лишней» делался по пустому ключу.
    @MainActor
    private static func поКличке(_ собаки: [Dog]) -> [String: [Dog]] {
        Dictionary(grouping: собаки.compactMap { d in d.nameIfAny.map { (d, $0) } },
                   by: \.1).mapValues { $0.map(\.0) }
    }

    @MainActor
    private static func поИмени(_ участники: [FamilyMember]) -> [String: [FamilyMember]] {
        Dictionary(grouping: участники.compactMap { m in Fmt.notBlank(m.name).map { (m, $0) } },
                   by: \.1).mapValues { $0.map(\.0) }
    }

    /// Что будет сделано, без единой правки. Смотреть до того, как жать.
    @MainActor
    static func план(in context: ModelContext) -> String {
        let собаки = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        let участники = (try? context.fetch(FetchDescriptor<FamilyMember>())) ?? []

        var строки: [String] = []
        for (кличка, группа) in поКличке(собаки) where группа.count > 1 {
            let по_дате = группа.sorted { $0.createdAt < $1.createdAt }
            let главная = по_дате[0]
            let переносим = по_дате.dropFirst().map(записейУ).reduce(0, +)
            строки.append("«\(кличка)»: \(группа.count) штуки. Оставлю заведённую "
                          + "\(главная.createdAt.formatted(date: .numeric, time: .shortened)), "
                          + "перенесу на неё \(переносим) связанных записей.")
        }
        for (имя, группа) in поИмени(участники) where группа.count > 1 {
            строки.append("Участник «\(имя)»: \(группа.count) штуки, оставлю одного.")
        }
        return строки.isEmpty ? "Дубликатов нет." : строки.joined(separator: "\n")
    }

    /// Слить. Возвращает, что сделано.
    @MainActor
    static func слить(in context: ModelContext) throws -> String {
        var итог: [String] = []

        let собаки = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        for (кличка, группа) in поКличке(собаки) where группа.count > 1 {
            let по_дате = группа.sorted { $0.createdAt < $1.createdAt }
            guard let главная = по_дате.first else { continue }
            var перенесено = 0
            for лишняя in по_дате.dropFirst() {
                перенесено += записейУ(лишняя)
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
                // Сохраняем до удаления: пока связи не записаны, каскад
                // унесёт их вместе с собакой.
                try context.save()
                context.delete(лишняя)
                try context.save()
            }
            итог.append("«\(кличка)»: слито, перенесено \(перенесено) записей.")
        }

        let участники = (try? context.fetch(FetchDescriptor<FamilyMember>())) ?? []
        var убрано = 0
        for (_, группа) in Dictionary(grouping: участники.filter { Fmt.notBlank($0.name) != nil },
                                      by: { "\($0.name)·\($0.roleRaw)" })
        where группа.count > 1 {
            // Оставляем того, кого ЭТО устройство считает собой.
            //
            // «Я» помнится на телефоне отдельно, ключом `family.me`
            // (AppState.myMemberID) — 22.09 это чинили именно потому, что
            // `isMe` в модели уезжал в общий дневник и «я» оказывалась
            // чужая карточка. Удалить того, на кого указывает ключ, —
            // значит вернуть ту же поломку: роль перестанет определяться,
            // и на телефоне снова будет «владелец» по умолчанию.
            let мой = UserDefaults.standard.string(forKey: "family.me").flatMap(UUID.init)
            let оставить = группа.first { $0.id == мой }
                ?? группа.first { $0.acceptedAt != nil }
                ?? группа[0]
            for лишний in группа where лишний !== оставить {
                context.delete(лишний)
                убрано += 1
            }
        }
        if убрано > 0 {
            try context.save()
            итог.append("Участников убрано: \(убрано).")
        }

        return итог.isEmpty ? "Дубликатов не нашлось." : итог.joined(separator: "\n")
    }

    @MainActor
    private static func записейУ(_ собака: Dog) -> Int {
        (собака.eventsStorage?.count ?? 0) + (собака.weightsStorage?.count ?? 0)
            + (собака.careTasksStorage?.count ?? 0) + (собака.medicationsStorage?.count ?? 0)
            + (собака.trainingStepsStorage?.count ?? 0) + (собака.trainingSessionsStorage?.count ?? 0)
            + (собака.tripsStorage?.count ?? 0) + (собака.documentsStorage?.count ?? 0)
            + (собака.daysOutStorage?.count ?? 0) + (собака.heatsStorage?.count ?? 0)
            + (собака.stocksStorage?.count ?? 0)
    }
}
#endif
