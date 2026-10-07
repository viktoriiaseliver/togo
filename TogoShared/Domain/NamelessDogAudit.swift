import Foundation
import SwiftData

/// Перепись безымянных записей о собаке. **Ничего не удаляет.**
///
/// **Этот файл начинал день удалятелем, и решение перевернулось
/// к вечеру — Викторией, с доводом.** История здесь не для красоты:
/// без неё следующий сочтёт отсутствие удаления недоделкой.
///
/// Утром знали: у человека восемь безымянных строк (отзыв TestFlight
/// 06.10.2026 по сборке 271), и убрать их он не может — кнопка удаления
/// существовала и была недостижима. Логично было убрать за него.
/// К вечеру стало известно три вещи, и каждая против удаления.
///
/// **1. Пустая запись может быть настоящей собакой на полпути.**
/// Крошки запуска с телефона: девять разных `id` за шесть дней, пять
/// исчезли сами. Вероятный источник — зеркало CloudKit, а оно создаёт
/// запись и заполняет атрибуты не одновременно. У такой записи нет
/// ни клички, ни связей, то есть от фантома она неотличима **ничем**,
/// включая оба прежних условия. Условие «видена пустой дважды» окно
/// сужало и не закрывало: при вставшей синхронизации настоящая собака
/// останется голой и через запуск. Померить это гонкой нечем — нужен
/// телефон с живым iCloud.
///
/// **2. Цена ошибки несимметрична, и «не показывать»
/// самоисправляется.**
///
/// ```
/// удалили лишнее       необратимо, уносит одиннадцать каскадов
/// не показали лишнее   обратимо: появится сама, когда доедет кличка
/// ```
///
/// **3. Удаление решало задачу, которой у человека нет.** Он жаловался
/// на строки на экране и на то, что их нечем убрать, — а не на записи
/// в базе. Скрытие закрывает обе жалобы; дорогу к удалению настоящей
/// собаки завели в тот же день.
///
/// **Что осталось и зачем.** Перепись. Она ничего не стирает, и именно
/// поэтому стала ценнее: по ней мы наконец узнаем, **копятся эти записи
/// или живут по одному дню** — вопрос, который до сегодня был
/// неизмерим. И если у безымянной записи окажется заполнено хоть
/// что-то, это укажет на семя, которого мы не нашли.
///
/// Скрытие живёт не здесь, а у правила показа: `Dog.canBeShown`
/// и `[Dog].shownToPerson`.
nonisolated enum NamelessDogAudit {

    /// Кого видели безымянным на прошлых запусках.
    private static let ключВиденыПустыми = "dogs.seenNameless"


    // MARK: Перепись

    /// Пересчитать безымянные записи и записать, что в них лежит.
    ///
    /// Зовётся при запуске **после** `DogOrigin.проверить`: перепись
    /// источников должна попасть в крошки первой.
    ///
    /// Возвращает, сколько безымянных записей найдено.
    @MainActor
    @discardableResult
    static func перепись(in context: ModelContext) -> Int {
        let собаки = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        let безымянные = собаки.filter { !$0.canBeShown }
        let былиПустыми = прочитать(ключВиденыПустыми)
        записать(Set(безымянные.map(\.id)), в: ключВиденыПустыми)

        for собака in безымянные {
            улика(собака, повторная: былиПустыми.contains(собака.id))
        }
        return безымянные.count
    }

    /// Что лежит в безымянной записи — в журнал действий и в крошки.
    ///
    /// **`повторная` и есть ответ на вопрос, который был неизмерим:**
    /// копятся эти записи или живут по одному дню. Удалятель этого
    /// не узнал бы никогда — он стирал бы улику раньше, чем она
    /// успевала накопиться.
    ///
    /// **Клички здесь нет и не будет**, в том числе у непустых полей:
    /// печатаются только ИМЕНА полей. Та же красная линия, что у крошек
    /// запуска и у `DogOrigin` — диагностический файл не становится
    /// личными данными.
    ///
    /// Зачем это вообще: восемь записей у человека — **единственные
    /// экземпляры дефекта**, семя которого мы не нашли. Если
    /// у безымянной записи окажется заполнено хоть что-то, это
    /// и будет указание на семя. Счёт по связям — нулями, чтобы
    /// «ничего не тянет» был видимым фактом, а не нашим словом.
    @MainActor
    private static func улика(_ dog: Dog, повторная: Bool) {
        let filled = непустыеПоля(dog)
        let rel = "ev \(dog.events.count) w \(dog.weights.count)"
            + " care \(dog.careTasks.count) med \(dog.medications.count)"
            + " step \(dog.trainingSteps.count) ses \(dog.trainingSessions.count)"
            + " trip \(dog.trips.count) doc \(dog.documents.count)"
            + " out \(dog.daysOut.count) heat \(dog.heats.count)"
            + " stock \(dog.stocks.count)"
        let iso = ISO8601DateFormatter()
        let line = "\(dog.id.uuidString.prefix(8))"
            + " created \(iso.string(from: dog.createdAt))"
            + " changed \(iso.string(from: dog.changedAt))"
            + " fields [\(filled.isEmpty ? "—" : filled.joined(separator: " "))]"
            + " rel [\(rel)]"

        UsageLog.note(.open, "namelessDog: \(line) seenBefore \(повторная ? 1 : 0)",
                      on: .settings)

        // **И в крошки запуска — потому что их нельзя выключить.**
        // `UsageLog.isOn` человек гасит в настройках приватности,
        // и это его право. Но удаление необратимо, а улика, которую
        // можно выключить тумблером, уликой не является: мы бы
        // удалили единственные экземпляры дефекта и не узнали даже,
        // что они были.
        //
        // Личного здесь нет ни в одном из двух файлов: ни клички,
        // ни заметок, ни граммов — восемь знаков идентификатора,
        // две даты, ИМЕНА заполненных полей и нули по связям.
        StartupLog.note("безымянная собака — \(line) видена раньше: \(повторная ? "да" : "нет")")
    }

    /// Имена заполненных полей. Значений нет ни у одного.
    ///
    /// Список руками, и это его слабое место: поле, добавленное
    /// в `Dog` завтра, здесь не появится, и улика промолчит о нём.
    /// Вывести из исходника, как это делает `DeviceLocalFieldTests`,
    /// отсюда нельзя — рефлексии по хранимым свойствам `@Model`
    /// у нас нет. Названо, а не спрятано.
    @MainActor
    private static func непустыеПоля(_ dog: Dog) -> [String] {
        var имена: [String] = []
        if dog.photo != nil { имена.append("photo") }
        if dog.breed?.isEmpty == false { имена.append("breed") }
        if dog.birthDate != nil { имена.append("birthDate") }
        if dog.weightKg != 0 { имена.append("weightKg") }
        if dog.targetWeightLow != nil { имена.append("targetWeightLow") }
        if dog.targetWeightHigh != nil { имена.append("targetWeightHigh") }
        if !dog.foodBrand.isEmpty { имена.append("foodBrand") }
        if dog.dailyNormGrams != nil { имена.append("dailyNormGrams") }
        if !dog.forbiddenFoods.isEmpty { имена.append("forbiddenFoods") }
        if !dog.rewards.isEmpty { имена.append("rewards") }
        if dog.isOnTreatment { имена.append("isOnTreatment") }
        if dog.chipNumber?.isEmpty == false { имена.append("chipNumber") }
        if dog.passportNumber?.isEmpty == false { имена.append("passportNumber") }
        if dog.insuranceNumber?.isEmpty == false { имена.append("insuranceNumber") }
        if dog.vetName?.isEmpty == false { имена.append("vetName") }
        if dog.vetPhone?.isEmpty == false { имена.append("vetPhone") }
        if dog.clinicName?.isEmpty == false { имена.append("clinicName") }
        if dog.clinicPhone?.isEmpty == false { имена.append("clinicPhone") }
        if dog.distinctiveMarks?.isEmpty == false { имена.append("distinctiveMarks") }
        if !dog.sitterFood.isEmpty { имена.append("sitterFood") }
        if !dog.sitterDose.isEmpty { имена.append("sitterDose") }
        if !dog.sitterWalks.isEmpty { имена.append("sitterWalks") }
        if !dog.sitterForbidden.isEmpty { имена.append("sitterForbidden") }
        if !dog.sitterEscalation.isEmpty { имена.append("sitterEscalation") }
        return имена
    }

    // MARK: Память

    private static func прочитать(_ ключ: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: ключ) ?? [])
            .compactMap(UUID.init(uuidString:)))
    }

    private static func записать(_ значение: Set<UUID>, в ключ: String) {
        UserDefaults.standard.set(значение.map(\.uuidString), forKey: ключ)
    }
}
