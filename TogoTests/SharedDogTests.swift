import Testing
import Foundation
import SwiftData
@testable import Togo

/// Собака ездит в общем дневнике.
///
/// Отзыв хозяйки за один вечер дважды: «у неё нет половины функционала»
/// и «мама не видит то же, что и я, **и не видит мою собаку**». Причина
/// была одна: общая зона возила два типа записей из семи, и собаки среди
/// них не было. Приглашение работало и приводило в пустую комнату.
@Suite("Профиль собаки в общем дневнике")
@MainActor
struct SharedDogTests {

    private func снимок(имя: String = "Стич", вес: Double = 4.1,
                        изменено: Date = Date()) -> DogPayload {
        DogPayload(
            id: UUID(), name: имя, breed: nil, birthDate: nil,
            sex: DogSex.unknown.rawValue, isNeutered: false, weightKg: вес,
            targetWeightLow: nil, targetWeightHigh: nil,
            foodBrand: "", portionGrams: 60, mealsPerDay: 2,
            mealTimes: [450, 1110], dailyNormGrams: nil, forbiddenFoods: [],
            wakeMinuteOfDay: 420, sleepMinuteOfDay: 1380,
            isOnTreatment: false, chipNumber: nil,
            passportNumber: nil, insuranceNumber: nil,
            vetName: nil, vetPhone: nil,
            clinicName: nil, clinicPhone: nil, distinctiveMarks: nil,
            sitterFood: "", sitterDose: "", sitterWalks: "",
            sitterForbidden: "", sitterEscalation: "",
            rewards: [], markerKind: MarkerKind.clicker.rawValue,
            sessionLengthMinutes: 3, trainingFoodFromPortion: true,
            changedAt: изменено
        )
    }

    /// Лист ситтера доезжает — то, ради чего он вообще существует.
    ///
    /// **До 05.10.2026 на втором телефоне он был пуст.** Пять полей
    /// хозяйка пишет один раз, ситтер только читает — а в нагрузке
    /// обмена их не было, и читать было нечего. Функция не работала
    /// в единственном сценарии, ради которого написана: в тот час,
    /// когда хозяина нет рядом.
    @Test("Лист ситтера приезжает к гостю целиком")
    func листСиттераПриезжает() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок()
        снимокСобаки.sitterFood = "60 г утром и вечером, Acana ягнёнок"
        снимокСобаки.sitterDose = "½ таблетки в 8:00, за полчаса до еды"
        снимокСобаки.sitterWalks = "7:00, 13:00, 19:00 — по 30 минут"
        снимокСобаки.sitterForbidden = "курица, кукуруза, чужие лакомства"
        снимокСобаки.sitterEscalation = "кровь или рвота — звонить сразу"

        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собака = try #require(try context.fetch(FetchDescriptor<Dog>()).first)
        #expect(собака.sitterFood == снимокСобаки.sitterFood)
        #expect(собака.sitterDose == снимокСобаки.sitterDose)
        #expect(собака.sitterWalks == снимокСобаки.sitterWalks)
        #expect(собака.sitterForbidden == снимокСобаки.sitterForbidden)
        #expect(собака.sitterEscalation == снимокСобаки.sitterEscalation, """
            лист для догситтера пуст на втором телефоне. Это не «работает
            частично»: лист существует ровно для того часа, когда хозяина
            нет рядом.
            """)
    }

    /// Два номера документов из трёх не ездили, а стояли в одной группе
    /// одного экрана с третьим.
    @Test("Номера паспорта и страховки приезжают вместе с чипом")
    func номераДокументовПриезжают() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок()
        снимокСобаки.chipNumber = "250269606000000"
        снимокСобаки.passportNumber = "FR 123456"
        снимокСобаки.insuranceNumber = "POL-77-2026"

        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собака = try #require(try context.fetch(FetchDescriptor<Dog>()).first)
        #expect(собака.chipNumber == снимокСобаки.chipNumber)
        #expect(собака.passportNumber == снимокСобаки.passportNumber)
        #expect(собака.insuranceNumber == снимокСобаки.insuranceNumber, """
            номер страховки нужен ровно в тот час, когда с собакой
            что-то случилось, а рядом не хозяин.
            """)
    }

    /// Лакомства из порции — не про дрессировку, а про еду.
    @Test("Гость считает дневную норму так же, как хозяйка")
    func нормаСчитаетсяОдинаково() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок()
        снимокСобаки.trainingFoodFromPortion = false
        снимокСобаки.rewards = ["сыр", "индейка"]
        снимокСобаки.sessionLengthMinutes = 7

        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собака = try #require(try context.fetch(FetchDescriptor<Dog>()).first)
        #expect(собака.trainingFoodFromPortion == false, """
            без этого поля гость считает дневную норму иначе хозяйки,
            и спорят они не о тренировке, а о том, сколько собака съела.
            """)
        #expect(собака.rewards == ["сыр", "индейка"])
        #expect(собака.sessionLengthMinutes == 7)
    }

    // MARK: Приём

    @Test("Приехавшая собака заводится у гостя")
    func собакаЗаводится() throws {
        let context = ModelContext(Persistence.container())
        let снимокСобаки = снимок(имя: "Стич", вес: 4.1)

        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)
        #expect(собаки.first?.id == снимокСобаки.id)
        #expect(собаки.first?.name == "Стич")
        #expect(собаки.first?.weightKg == 4.1)
    }

    /// Решение Виктории от 23.09.2026: обе, переключателем. Слияния
    /// по кличке быть не должно ни при каких условиях — две «Стич»
    /// в одном доме это две собаки, и живой дневник 23.09 разошёлся
    /// пополам именно так.
    @Test("Своя собака гостя остаётся рядом с приехавшей")
    func двеСобакиЖивутРядом() throws {
        let context = ModelContext(Persistence.container())
        let своя = Dog(name: "Стич", weightKg: 4.0)
        context.insert(своя)
        try context.save()

        SharedDiaryInbox.accept(снимок(имя: "Стич", вес: 4.1), context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 2, "приехавшая собака слилась со своей по кличке")
        #expect(собаки.contains { $0.weightKg == 4.0 })
        #expect(собаки.contains { $0.weightKg == 4.1 })
    }

    @Test("Повторный приезд правит ту же собаку, а не заводит вторую")
    func повторНеДублирует() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок(вес: 4.1, изменено: Date())
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        снимокСобаки.weightKg = 4.4
        снимокСобаки.changedAt = Date().addingTimeInterval(60)
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1)
        #expect(собаки.first?.weightKg == 4.4)
    }

    // MARK: Спор

    @Test("Побеждает правка, что позже")
    func позжеПобеждает() {
        let раньше = снимок(вес: 4.0, изменено: Date())
        var позже = раньше
        позже.weightKg = 4.5
        позже.changedAt = раньше.changedAt.addingTimeInterval(30)

        #expect(SharedDiaryMerge.resolve(local: раньше, remote: позже).weightKg == 4.5)
        #expect(SharedDiaryMerge.resolve(local: позже, remote: раньше).weightKg == 4.5)
    }

    /// Часы двух телефонов расходятся на секунды. При ничьей разумнее
    /// взять ту версию, где данных больше, чем ту, где их стёрли.
    @Test("При ничьей выигрывает заполненное")
    func ничьяЗаЗаполненным() {
        let момент = Date()
        var пустая = снимок(изменено: момент)
        var полная = пустая
        полная.breed = "мальтипу"
        полная.vetName = "Клиника на углу"
        полная.chipNumber = "250269"
        пустая.breed = nil

        #expect(SharedDiaryMerge.resolve(local: пустая, remote: полная).breed == "мальтипу")
        #expect(SharedDiaryMerge.resolve(local: полная, remote: пустая).breed == "мальтипу")
    }

    /// Вкладка «Здоровье» приходит с курсом лечения. Если `isOnTreatment`
    /// не доедет, гость отмечает приёмы, которые ему негде посмотреть.
    @Test("Лечение доезжает вместе с профилем")
    func лечениеДоезжает() throws {
        let context = ModelContext(Persistence.container())
        var снимокСобаки = снимок()
        снимокСобаки.isOnTreatment = true
        SharedDiaryInbox.accept(снимокСобаки, context: context)

        let собака = try context.fetch(FetchDescriptor<Dog>()).first
        #expect(собака?.isOnTreatment == true)
    }

    // MARK: Кодирование

    @Test("Снимок переживает дорогу через CloudKit без потерь")
    func полеНеТеряется() throws {
        var исходный = снимок(имя: "Багира", вес: 5.2)
        исходный.breed = "такса"
        исходный.birthDate = Date(timeIntervalSince1970: 1_600_000_000)
        исходный.isNeutered = true
        исходный.targetWeightLow = 4.8
        исходный.targetWeightHigh = 5.5
        исходный.foodBrand = "Acana"
        исходный.dailyNormGrams = 180
        исходный.forbiddenFoods = ["виноград", "шоколад"]
        исходный.isOnTreatment = true
        исходный.chipNumber = "250269"
        исходный.vetName = "Мари"
        исходный.vetPhone = "+33..."
        исходный.clinicName = "Клиника на углу"
        исходный.clinicPhone = "+33..."
        исходный.distinctiveMarks = "белое пятно на груди"

        let зона = SharedDiaryRecords.zoneID()
        let запись = SharedDiaryRecords.record(исходный, in: зона)
        let вернувшийся = try #require(SharedDiaryRecords.dogPayload(запись))

        #expect(вернувшийся == исходный, """
            поле потерялось по дороге. Сравнение целиком, а не по одному:
            у словаря нельзя проверить тестом, что при переименовании
            ничего не выпало.
            """)
    }

    /// Ключа `name` нет вовсе.
    ///
    /// **Этот тест был один, и он отвечал не на то утверждение, рядом
    /// с которым стоял.** Над `dogPayload` написано «кличка
    /// обязательна… лучше не заводить вовсе, чем завести безымянной»,
    /// а `guard let name = record["name"] as? String` спрашивает, **есть
    /// ли ключ**. Пустая строка — ключ есть, тип верен — проходила
    /// насквозь, и тест это подтверждал, потому что проверял отсутствие
    /// ключа. Два соседа ниже закрывают оба края.
    @Test("Запись без клички не принимается")
    func безКличкиНеПринимается() {
        let зона = SharedDiaryRecords.zoneID()
        let запись = SharedDiaryRecords.record(снимок(), in: зона)
        запись["name"] = nil
        #expect(SharedDiaryRecords.dogPayload(запись) == nil, """
            собака без клички — это не «пустое имя», а запись, которую
            нечем показать в переключателе.
            """)
    }

    /// Граница, названная при охоте за семенем пустых кличек 07.10.2026.
    ///
    /// `Dog.id` объявлен без `@Attribute(.unique)`. Значит хранилище
    /// **не склеивает** две записи с одним `id` и не мешает завести
    /// третью: единственное, что нас от этого спасает, — выборка
    /// по `id` в `SharedDiaryInbox.accept`, то есть наш код, а не
    /// устройство базы.
    ///
    /// Записано тестом, а не комментарием, потому что из этого факта
    /// следует: **любой путь, заводящий `Dog` мимо `accept`, дублирует
    /// молча.** Зеркало SwiftData — ровно такой путь: записи оно кладёт
    /// само, нашего кода не спрашивая.
    ///
    /// Семенем это не является и версией не становится: здесь измерено
    /// только то, что база дубликату не мешает.
    @Test("Хранилище не склеивает двух собак с одним id — это делает наш код")
    func хранилищеНеСклеиваетПоId() throws {
        let context = ModelContext(Persistence.container())
        let один = UUID()
        let первая = Dog(name: "Стич", weightKg: 4.7)
        первая.id = один
        let вторая = Dog(name: "", weightKg: 0)
        вторая.id = один
        context.insert(первая)
        context.insert(вторая)
        try context.save()

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 2, """
            хранилище склеило или отвергло запись с тем же `id` —
            значит у `Dog.id` появилась уникальность, и рассуждение
            «мимо accept дублируется молча» больше не верно. Проверь
            `SharedDiaryInbox.accept`: его выборка по `id` могла стать
            лишней, а могла стать единственной защитой от потери
            данных при склейке.
            """)
    }

    /// Четвёртая поверхность, и единственная, где мы не получаем
    /// мусор, а **рассылаем его другому человеку**.
    ///
    /// Безымянная собака, уже лежащая в базе, публиковалась в общую
    /// зону, и на втором телефоне её принимал тот самый `accept`,
    /// который закрыт на входе. Уборка это не закрыла бы: она удаляет
    /// только безымянное без истории, а безымянную с историей мы храним
    /// нарочно — и публиковалась бы дальше ровно она.
    @Test("Безымянная собака наружу не отправляется")
    func безымяннаяНеОтправляется() {
        let зона = SharedDiaryRecords.zoneID()
        var пустая = снимок()
        пустая.name = ""

        #expect(SharedDiaryRecords.record(пустая, base: nil, in: зона) == nil, """
            безымянная собака ушла в общую зону. Это единственная
            поверхность дефекта, где мусор не приходит к нам, а уходит
            от нас к другому человеку.
            """)
    }

    /// Обратный край: «ничего не отправляется» выполняется и тогда,
    /// когда не отправляется вообще ничего.
    @Test("Собака с кличкой отправляется, и в записи стоит её кличка")
    func сКличкойОтправляется() throws {
        let зона = SharedDiaryRecords.zoneID()
        let обычная = снимок(имя: "Стич")

        let запись = try #require(SharedDiaryRecords.record(обычная, base: nil, in: зона), """
            собака с кличкой не отправилась — ворота против пустой
            клички закрыли дорогу всем.
            """)
        #expect(запись["name"] as? String == "Стич")
        #expect(запись.recordID.recordName == обычная.id.uuidString)
    }

    /// Отзыв TestFlight 06.10.2026, сборка 271: «Много пустых собак».
    ///
    /// На кадре в «Настройках» одна настоящая собака и **восемь строк
    /// без подписи с „0,0 г“**. Это ровно `Dog` со значениями
    /// по умолчанию (`name = ""`, `weightKg = 0`): подпись строки —
    /// `dog.name`, а `Fmt.weight` при нуле печатает граммы, потому что
    /// `Measurement` с `usage: .personWeight` сама меняет единицу.
    ///
    /// Путь приёма был открыт на обоих концах: `dogPayload` пускала
    /// пустую кличку, `accept` заводила по ней собаку.
    @Test("Пустая кличка — не кличка: запись не принимается")
    func пустаяКличкаНеПринимается() {
        let зона = SharedDiaryRecords.zoneID()

        for пустая in ["", " ", "\n", "\u{00A0}"] {
            let запись = SharedDiaryRecords.record(снимок(), in: зона)
            запись["name"] = пустая
            #expect(SharedDiaryRecords.dogPayload(запись) == nil, """
                кличка \(пустая.debugDescription) принята как кличка.
                Отзыв 06.10: «Много пустых собак» — восемь строк без
                подписи с «0,0 г». Проверка «есть ли ключ» выполняется
                и при пустом значении, то есть при самом дефекте.
                """)
        }
    }

    /// Вторая половина того же места, и она дороже первой.
    ///
    /// У существующей собаки `accept` идёт в слияние, где **побеждает
    /// поздняя правка целиком**. Пустой снимок с более поздним
    /// `changedAt` затирал кличку живой собаки — то есть пустые собаки
    /// не только заводились, но и **делались из настоящих**.
    ///
    /// Проверка стоит на `accept`, а не на `dogPayload`: фильтр
    /// на разборе записи закрывает дорогу из CloudKit, а обнуляет
    /// собаку шаг вставки. Сторожить надо то место, где теряется
    /// кличка, а не то, через которое она приехала.
    @Test("Пустой снимок не обнуляет кличку живой собаки")
    func пустойСнимокНеЗатираетКличку() throws {
        let context = ModelContext(Persistence.container())
        let живая = Dog(name: "Стич", weightKg: 4.7)
        context.insert(живая)
        try context.save()

        var пустой = снимок()
        пустой.id = живая.id
        пустой.name = ""
        пустой.weightKg = 0
        пустой.changedAt = живая.changedAt.addingTimeInterval(3600)

        SharedDiaryInbox.accept(пустой, context: context)

        let собаки = try context.fetch(FetchDescriptor<Dog>())
        #expect(собаки.count == 1, """
            приехал снимок уже известной собаки, а их стало
            \(собаки.count).
            """)
        #expect(собаки.first?.name == "Стич", """
            кличка живой собаки обнулена приехавшим пустым снимком.
            «Позже побеждает» верно для веса и порции — это факты,
            которые уточняют. Для клички оно означает, что собака
            у человека на экране пропадает без его участия.
            """)
        #expect(собаки.first?.weightKg == 4.7)
    }

    // MARK: Привязка ленты

    @Test("Приехавшая запись цепляется к своей собаке, а не к первой")
    func записьИщетСвоюСобаку() throws {
        let context = ModelContext(Persistence.container())
        let чужая = Dog(name: "Стич", weightKg: 4.1)
        let своя = Dog(name: "Багира", weightKg: 5.2)
        context.insert(чужая)
        context.insert(своя)
        try context.save()

        var запись = EventPayload(
            id: UUID(), dogID: своя.id, kind: LogKind.meal.rawValue, date: Date(),
            authorName: "Мама", note: nil, outcome: nil, durationSeconds: nil,
            stoolForm: nil, stoolFlags: [], grams: 65, milliliters: nil,
            fromPortion: false, incidentKind: nil, incidentDetail: nil,
            walkEventID: nil, careTaskID: nil, medicationID: nil,
            deletedAt: nil, deletedBy: nil, changedAt: Date()
        )
        #expect(SharedDiaryInbox.dog(for: запись, context: context)?.id == своя.id)

        // Собаки, которой нет, — и двух местных: лучше ничья, чем
        // приписанная не тому животному. Ничью видно и можно починить.
        запись.dogID = UUID()
        #expect(SharedDiaryInbox.dog(for: запись, context: context) == nil)
    }

    @Test("Когда собака одна, запись без известного id достаётся ей")
    func однаСобакаЗабираетНичью() throws {
        let context = ModelContext(Persistence.container())
        let одна = Dog(name: "Стич", weightKg: 4.1)
        context.insert(одна)
        try context.save()

        let запись = EventPayload(
            id: UUID(), dogID: UUID(), kind: LogKind.meal.rawValue, date: Date(),
            authorName: "Мама", note: nil, outcome: nil, durationSeconds: nil,
            stoolForm: nil, stoolFlags: [], grams: 65, milliliters: nil,
            fromPortion: false, incidentKind: nil, incidentDetail: nil,
            walkEventID: nil, careTaskID: nil, medicationID: nil,
            deletedAt: nil, deletedBy: nil, changedAt: Date()
        )
        #expect(SharedDiaryInbox.dog(for: запись, context: context)?.id == одна.id, """
            записи, уехавшие до того, как профиль научился ездить, помнят
            чужой dogID. Когда собака одна, ошибиться невозможно.
            """)
    }
}
