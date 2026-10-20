import Foundation
import SwiftData

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var name: String = ""
    var roleRaw: String = FamilyRole.helper.rawValue
    var note: String?
    var isMe: Bool = false

    /// Права, выданные поимённо. Пусто — значит «по роли»: так видно
    /// разницу между «мы ничего не меняли» и «мы всё сняли руками».
    var customPermissionsRaw: [String]?

    /// Дежурный получает напоминания; передача дежурства — одно действие.
    var isOnDuty: Bool = false
    var dutyUntil: Date?

    /// **Четыре поля, за которыми нет механизма. Замер 14.10.2026.**
    ///
    /// Прежняя редакция этой строки обещала: «приглашение живёт 24 часа,
    /// роль фиксируется до принятия, ссылка ситтера гаснет по дате сама».
    /// Ни одного из трёх в коде нет:
    ///
    /// - `inviteToken` и `inviteExpiresAt` пишет только
    ///   `OnboardingSteps.swift:332` — там кнопка «Отправить ссылку»
    ///   заводит **локального** участника и никакого `CKShare`
    ///   не создаёт; настоящее приглашение идёт мимо этих полей
    ///   (`FamilyShare.invite` → лист «Поделиться»);
    /// - `accessExpiresAt` **человеком не пишется нигде**: только
    ///   `CloudKitSchemaWarmup` под `#if DEBUG` и восстановление
    ///   из архива. Гашения доступа по дате в коде нет вовсе —
    ///   ни таймера, ни проверки при входе;
    /// - роль после принятия выбирает **сам принявший**, у себя
    ///   на телефоне: `FamilyMember` по обмену не ездит
    ///   (`SharedDiary.swift:78`, решение 08.10).
    ///
    /// Поля оставлены: они в форме схемы `5.0.0`, снести их значит
    /// сменить форму под неизменным номером — то самое, что даёт
    /// «Дневник не открылся». Но доккомментарий больше не обещает
    /// механизма: обещание читает тот, кто пишет экран, и однажды
    /// оно уже доехало до человека баннером `FamilyScreen.swift:409`.
    var inviteToken: String?
    var inviteExpiresAt: Date?
    var accessExpiresAt: Date?
    var acceptedAt: Date?

    init(name: String, role: FamilyRole, isMe: Bool = false) {
        self.name = name
        self.roleRaw = role.rawValue
        self.isMe = isMe
    }

    var role: FamilyRole {
        get { FamilyRole(rawValue: roleRaw) ?? .helper }
        set { roleRaw = newValue.rawValue }
    }

    var initial: String { String(name.prefix(1)).uppercased() }

    /// Итоговый набор прав: свой, если его выдавали, иначе — из роли.
    var permissions: Set<Permission> {
        get {
            guard let raw = customPermissionsRaw else { return role.defaultPermissions }
            return Set(raw.compactMap(Permission.init))
        }
        set {
            // Владельца нельзя оставить без управления семьёй: иначе
            // права станет некому раздавать.
            var next = newValue
            if role == .owner { next.insert(.manageFamily) }
            customPermissionsRaw = next == role.defaultPermissions ? nil : next.map(\.rawValue).sorted()
        }
    }

    /// Права отличаются от роли — это стоит показать в интерфейсе.
    var hasCustomPermissions: Bool { customPermissionsRaw != nil }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// Вернуть к набору по роли.
    func resetPermissions() { customPermissionsRaw = nil }

    var isInvitePending: Bool { acceptedAt == nil && inviteToken != nil }

    /// Вызовов нет (замер 20.10.2026): срок пишется и не читается.
    /// Поставить его в условие — решение о механизме, не правка текста.
    func inviteIsValid(at date: Date = Date()) -> Bool {
        guard let inviteExpiresAt else { return false }
        return date < inviteExpiresAt
    }
}

/// Эпизод: два инцидента за 24 часа или подряд идущие дни с жидким стулом.
/// Пока эпизод активен, вердикт «просится» не считается вовсе.
@Model
final class Episode {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    /// Когда был последний инцидент этого эпизода. От него и считается,
    /// закончился ли он.
    var lastIncidentAt: Date = Date()
    var title: String = ""
    var detail: String = ""

    init(title: String, detail: String, startedAt: Date = Date()) {
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
        self.lastIncidentAt = startedAt
    }

    /// Сколько тишины считается концом эпизода.
    ///
    /// Двое суток без новых инцидентов — значит, прошло. Раньше эпизод
    /// не заканчивался никогда: `endedAt` не выставлял никто, а `isActive`
    /// без него возвращал `true`. То есть после двух инцидентов за сутки
    /// вердикт «просится» замолкал навсегда — и человек не понимал, почему
    /// приложение перестало подсказывать.
    ///
    /// **Величина и правило живут в `EpisodeLifetime`, здесь только
    /// адрес.** До 08.10.2026 число `48 * 3600` стояло в двух файлах,
    /// и `isActive` было написано дважды — в модели и в домене, слово
    /// в слово. Совпадали они случайно: домен **не вызывался ниоткуда**
    /// (замер: `grep EpisodeLifetime` по дереву давал только объявление
    /// и одну ссылку в комментарии), то есть расходиться им было негде.
    ///
    /// > **Две копии одного числа не расходятся, пока вторую никто
    /// > не зовёт. Первая же правка разведёт их молча.**
    ///
    /// Это тот самый случай, ради которого домен и писали: у него
    /// в голове прямо сказано, что `Episode.isActive` должен звать
    /// отсюда, а не повторять. Правило спрашивают три поверхности —
    /// главный экран, виджет и «остров», — и третья реализация у Togo
    /// уже стоила молчащего окна «не кормить».
    static var quietPeriod: TimeInterval { EpisodeLifetime.quietPeriod }

    /// Активен ли эпизод. Порядок проверок — часть смысла, и он тоже
    /// в домене: объявленный конец сильнее тишины, иначе нажатое
    /// «закончился» отменялось бы недавним инцидентом.
    func isActive(at date: Date = Date()) -> Bool {
        EpisodeLifetime.isActive(lastIncidentAt: lastIncidentAt,
                                 endedAt: endedAt, now: date)
    }

    /// Продлить: случился ещё один инцидент.
    func extend(to date: Date = Date()) {
        lastIncidentAt = max(lastIncidentAt, date)
        endedAt = nil
    }

    /// Закрыть руками: человек видит, что собаке лучше.
    func close(at date: Date = Date()) {
        endedAt = date
    }

    /// Когда эпизод закончится сам, если больше ничего не случится.
    var quietUntil: Date {
        lastIncidentAt.addingTimeInterval(Self.quietPeriod)
    }
}

/// Поездка включается датой и гаснет сама. Это режим, а не раздел:
/// устроена как «Фокус», а не как место, куда надо ходить.
@Model
final class Trip {
    var id: UUID = UUID()
    var destination: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var transportRaw: String = TransportKind.car.rawValue
    var travelHours: Double = 0
    var lodging: String = ""
    var participants: [String] = []
    var departureMinuteOfDay: Int = 9 * 60
    var packedItems: [String] = []

    var dog: Dog?

    init(destination: String, startDate: Date, endDate: Date, transport: TransportKind) {
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.transportRaw = transport.rawValue
    }

    var transport: TransportKind {
        get { TransportKind(rawValue: transportRaw) ?? .car }
        set { transportRaw = newValue.rawValue }
    }

    // **Календарь аргументом, а не `Calendar.current` внутри.** Он несёт
    // пояс ЧИТАЮЩЕГО, и пока он брался внутри, проверить эти три функции
    // по поясам было нечем: поверхность непроверяемая, а чинится такое
    // переделкой входа, а не старанием. Замер 05.10 — в `CalendarDay`.
    //
    // По умолчанию — `CalendarDay.дневниковыйКалендарь`, а НЕ `.current`:
    // день записи у общего дневника один на семью, иначе двое читают
    // разные числа из одной строки. Для заякоренных записей выбор пояса
    // не меняет ничего (полдень устойчив к ±12 часам); он решает только
    // судьбу записей до 05.10, у которых якоря нет. Допущение, на котором
    // это держится, названо в `CalendarDay.дневниковыйПояс` вместе с тем,
    // что его снимет.

    func dayCount(calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Int {
        max(1, CalendarDay.daysBetween(startDate, endDate, calendar: calendar) + 1)
    }

    func isActive(on date: Date = Date(), calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Bool {
        let from = calendar.startOfDay(for: startDate)
        // Последний день поездки считается целиком: возвращаются вечером.
        guard let until = calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: endDate)) else {
            return false
        }
        return date >= from && date <= until
    }

    func dayNumber(on date: Date = Date(), calendar: Calendar = CalendarDay.дневниковыйКалендарь) -> Int {
        CalendarDay.daysBetween(startDate, date, calendar: calendar) + 1
    }
}
