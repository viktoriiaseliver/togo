import Foundation
import SwiftData

/// Уборка безымянных записей о собаке при запуске.
///
/// **Зачем это вообще есть.** Отзыв TestFlight 06.10.2026 по сборке
/// 271: «Много пустых собак» — у человека одна настоящая собака
/// и восемь строк без подписи. Пути, которыми они заводились, закрыты
/// (`SharedDiaryRecords.dogPayload`, `SharedDiaryInbox.accept`,
/// `BackupService.restore`, `SharedDiaryRecords.record(_:base:in:)`),
/// но уже лежащие записи от этого не исчезают, а удалить их человек
/// до 07.10 не мог вовсе: кнопка удаления существовала и была
/// недостижима.
///
/// Решение удалять — Виктории, 07.10.2026. Порядок и условия —
/// менеджера дня и этой сессии; ниже каждое условие с доводом, потому
/// что удаление необратимо, а семя пустых кличек мы не нашли.
///
/// **Чего здесь нельзя принять замером, и это сказано вслух.** Крошки
/// запуска с телефона Виктории показывают девять разных `id` за шесть
/// дней и пять исчезновений: зеркало CloudKit заводит такие строки
/// и правит свои же **прямо сейчас**. Значит бывает ли окно, когда
/// настоящая собака выглядит безымянной, — вопрос к живому iCloud
/// на телефоне, а не к этому коду. Он открыт. Условие 3 снимает гонку
/// не замером, а отказом в верную сторону.
nonisolated enum NamelessDogCleanup {

    /// Кого видели безымянным на прошлых запусках.
    private static let ключВиденыПустыми = "dogs.seenNameless"

    /// Кого убрали мы сами. Нужно не нам, а `DogOrigin`: без этого
    /// множества он напечатает про нашу уборку «исчезла» — тем же
    /// словом, которым говорит о пропажах, причины которых мы ищем.
    ///
    /// **Одно слово на две причины хуже молчания**, и цена здесь
    /// названа: «исчезла сама» — единственная улика по зеркалу,
    /// которого мы не понимаем. Разбавить её своими уборками значит
    /// завтра не отличить поведение зеркала от своей работы.
    private static let ключУбраныНами = "dogs.removedByCleanup"

    static var убраныНами: Set<UUID> {
        get { прочитать(ключУбраныНами) }
        set { записать(newValue, в: ключУбраныНами) }
    }

    // MARK: Условия

    /// Подлежит удалению — **три условия, и каждое обязательно**.
    ///
    /// 1. **Безымянна.** Правило одно на весь проект — `Fmt.dogName`,
    ///    то же, что на приёме снимка и в показе. Пробелы и U+00A0
    ///    считаются пустотой.
    ///
    /// 2. **Ничего за собой не тянет.** У `Dog` одиннадцать связей,
    ///    и у всех одиннадцати `deleteRule: .cascade`: удаление уносит
    ///    весь дневник. Поэтому «безымянна» — условие недостаточное:
    ///    **безымянной бывает настоящая собака, которой кличку затёрло
    ///    слиянием** (дефект измерен и починен 07.10 в том же дне).
    ///    Безымянная с историей не трогается ничем — ни удалением,
    ///    ни пряткой: это улика о семени, которого мы не нашли,
    ///    и человеку она важнее нашей чистоты.
    ///
    /// 3. **Была безымянной и на прошлом запуске.** Это про гонку
    ///    с зеркалом, а не про осторожность: зеркало правит свои же
    ///    строки, и запись, пустая в момент запуска, через секунду
    ///    может стать Стичем. Таймаут («старше пяти минут») пришлось
    ///    бы выдумать; «видели дважды» — наблюдение.
    ///
    ///    Отказ отложенной уборки стоит человеку одного лишнего
    ///    запуска с пустыми строками. Ошибка в другую сторону стоит
    ///    ему дневника.
    ///
    ///    Память живёт в `UserDefaults` и переустановку не переживает:
    ///    после переустановки уборка пропустит первый запуск. Это
    ///    верная сторона отказа.
    @MainActor
    static func подлежитУдалению(_ dog: Dog, виденыПустыми: Set<UUID>) -> Bool {
        dog.nameIfAny == nil
            && ничегоНеТянет(dog)
            && виденыПустыми.contains(dog.id)
    }

    /// Все одиннадцать связей пусты.
    ///
    /// Перечислены **целиком и рядом с тем, что решают**. Сторожа
    /// на полноту этого перечня нет; появится двенадцатая связь —
    /// здесь её не будет, и безымянная собака с записями нового вида
    /// исчезнет молча. Поэтому список стоит в одном месте, а не
    /// в трёх по кусочку.
    ///
    /// **Второй способ ссылки проверять не нужно, и это замер,
    /// а не допущение.** Менеджер предложил добавить сюда выборку
    /// «ни одна запись не ссылается на `dog.id` полем `dogID`».
    /// Померено 07.10: `dogID` существует **только в снимках обмена**
    /// (`SharedDiary.swift` — `EventPayload`, `CarePayload`,
    /// `MedicationPayload`), и ни у одной `@Model` такого хранимого
    /// поля нет. Проверка была бы истинной всегда — то есть
    /// исключением, закрывающим то, чего нет, и дырой, про которую
    /// никто не помнит.
    ///
    /// Вместо неё заведён сторож `NamelessDogCleanupTests`: он падает,
    /// если у какой-нибудь модели появится хранимое `dogID`. Риск
    /// настоящий, но будущий, и ловить его надо тестом, а не мёртвой
    /// веткой.
    ///
    /// *Проверка за минуту: `grep -rn "var dogID" TogoShared/Models`
    /// → ничего.*
    @MainActor
    static func ничегоНеТянет(_ dog: Dog) -> Bool {
        dog.events.isEmpty
            && dog.weights.isEmpty
            && dog.careTasks.isEmpty
            && dog.medications.isEmpty
            && dog.trainingSteps.isEmpty
            && dog.trainingSessions.isEmpty
            && dog.trips.isEmpty
            && dog.documents.isEmpty
            && dog.daysOut.isEmpty
            && dog.heats.isEmpty
            && dog.stocks.isEmpty
    }

    // MARK: Уборка

    /// Убрать безымянные записи и записать, что убрали.
    ///
    /// Зовётся при запуске **после** `DogOrigin.проверить`: перепись
    /// должна попасть в крошки до удаления, иначе убранного в журнале
    /// не останется вовсе.
    ///
    /// Возвращает, сколько убрано.
    @MainActor
    @discardableResult
    static func убрать(in context: ModelContext) -> Int {
        let собаки = (try? context.fetch(FetchDescriptor<Dog>())) ?? []
        let былиПустыми = прочитать(ключВиденыПустыми)

        let безымянные = собаки.filter { $0.nameIfAny == nil }
        // Память о пустых обновляем ДО удаления и по всем безымянным,
        // а не только по убранным: безымянная с историей не убирается
        // никогда, но числиться в списке должна — иначе, лишившись
        // истории по воле человека, она начнёт отсчёт заново.
        записать(Set(безымянные.map(\.id)), в: ключВиденыПустыми)

        let кУдалению = безымянные.filter {
            ничегоНеТянет($0) && былиПустыми.contains($0.id)
        }
        guard !кУдалению.isEmpty else { return 0 }

        for собака in кУдалению { улика(собака) }

        let было = убраныНами
        for собака in кУдалению { context.delete(собака) }
        guard context.persist(otherwise: { убраныНами = было }) else {
            // Не сохранилось — значит не убрано, и говорить об этом надо
            // там же, где говорили об уборке: иначе в журнале останется
            // «убрана» без «не вышло», и следующий решит, что записи
            // удалены.
            StartupLog.note("уборка безымянных не сохранилась — записи на месте")
            return 0
        }
        убраныНами = было.union(кУдалению.map(\.id))
        return кУдалению.count
    }

    /// Что именно убрали — в журнал действий, до удаления.
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
    private static func улика(_ dog: Dog) {
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

        UsageLog.note(.open, "namelessDogRemoved: \(line)", on: .settings)

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
        StartupLog.note("убрана безымянная собака — \(line)")
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
