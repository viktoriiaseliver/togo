import SwiftUI
import SwiftData
import Observation

/// Четыре флага определяют почти всё, что видно на экранах.
/// Ни один не переключается вручную с главного — все включаются событием или датой.
@Observable
final class AppState {
    /// В какой день пишутся новые записи. Пусто — в сегодняшний.
    ///
    /// **Живёт здесь, а не в главном экране, нарочно.** Листы записи
    /// раздаёт `TodayRouter`, и до 28.09 ни один из десяти не знал
    /// о показываемом дне: каждый брал `Date()` внутри себя. Провести
    /// день до всех десяти по одному значило бы десять правок и десять
    /// мест, где о нём забудут. `AppState` есть у каждого листа уже
    /// сейчас, и `EventLog` держит его в руках — поэтому день доезжает
    /// до записи одной дорогой.
    ///
    /// Ставится только листалкой дня на «Сегодня» и снимается ею же.
    var деньЗаписи: Date?

    /// Момент, которым записывать. Сегодня — настоящие часы.
    ///
    /// В прошлом дне часов не существует, и подставляется **тот же час,
    /// что сейчас, но в тот день**: пишешь вчерашнюю еду в три часа дня —
    /// ляжет вчера в три часа дня. Это догадка, и она названа человеку
    /// в подтверждении («Записано · вчера, 15:00»), а не подсунута
    /// молча. Поправить час можно в самой записи: с 28.09 у неё
    /// правится и день, и время.
    ///
    /// Час, который был бы честнее догадки, — спрошенный. Он спрашивается
    /// там, где вопрос дешёвый: у пункта плана дня, где есть назначенное
    /// время (`GivenAtSheet`). У свободной кнопки спрашивать не у чего.
    var моментЗаписи: Date {
        guard let деньЗаписи else { return Date() }
        let cal = Calendar.current
        let сейчас = Date()
        let часы = cal.dateComponents([.hour, .minute, .second], from: сейчас)
        let вТотДень = cal.date(bySettingHour: часы.hour ?? 12,
                                minute: часы.minute ?? 0,
                                second: часы.second ?? 0,
                                of: деньЗаписи) ?? деньЗаписи
        // За сегодня не заходим никогда: запись в будущем ломает всё,
        // что считается «от последнего раза».
        return min(вТотДень, сейчас)
    }

    /// Пишем ли мы сейчас не в сегодняшний день.
    var записьВПрошлое: Bool {
        guard let деньЗаписи else { return false }
        return !Calendar.current.isDateInToday(деньЗаписи)
    }

    /// Роль текущего человека на этом телефоне.
    ///
    /// **Начальное значение самое узкое, а не самое широкое.**
    /// До 23.09.2026 здесь стоял `.owner`, а `.owner` — это
    /// `Set(Permission.allCases)`, все права до единого. `init()` роль
    /// с диска не восстанавливает, так что каждый запуск начинался
    /// с полных прав, и `adoptMe` их только подтверждал или оставлял
    /// как есть.
    ///
    /// Стреляло это на втором телефоне: гость принял приглашение,
    /// участников двое и больше, своя карточка не запомнена —
    /// `adoptMe` возвращался ни с чем, и приглашённый наблюдателем
    /// получал `editTreatment`, `manageFamily`, `exportData`. Ровно
    /// тот случай, ради которого права и заведены.
    ///
    /// Теперь отказ **закрывает**, а не открывает. Права выдаёт
    /// `adoptMe`, и он же решает, что значит «не опознали».
    var role: FamilyRole = .observer {
        didSet { if customPermissions != nil { customPermissions = nil } }
    }
    /// Права, выданные ему поимённо. Пусто — значит «по роли».
    var customPermissions: Set<Permission>?

    /// Экраны спрашивают про право, а не про роль: роль — это пресет,
    /// и владелец может его переопределить для любого участника.
    /// Потолок гостя применяется **здесь**, а не в `adopt`: роль
    /// и права кладутся в поля один раз при запуске, а гостем человек
    /// может стать позже — приняв приглашение в уже открытом
    /// приложении. Проверка в месте чтения переживает смену флага;
    /// проверка в месте записи — нет.
    ///
    /// Само правило — одно, в `FamilyResolver.потолокГостя`: второй
    /// вход (голос, кнопка «Действие», виджет) зовёт его же через
    /// `FamilyResolver.права`. Там же записано, чем он заменится,
    /// когда роль поедет по обмену.
    /// **Вызов собран в одну строку нарочно — чтобы его можно было
    /// снять подделкой.** `make guard` заменяет ПОДСТРОКУ, а вызов,
    /// разнесённый на две строки, одной заменой не снимается:
    /// подделка бы не применилась, прогон вышел бы зелёным,
    /// и зелёное на неприменённой подделке читается как «сторож
    /// не ловит» — вывод, обратный правде.
    ///
    /// Поведение прежнее: подвыражение вынесено в `своиПрава`,
    /// ни одной новой ветки. Это тот же случай, что с кадром:
    /// **прежде чем проверять поверхность, надо проверить, что её
    /// МОЖНО проверить; непроверяемое лечится переделкой входа,
    /// а не старанием.**
    var permissions: Set<Permission> {
        FamilyResolver.потолокГостя(своиПрава, гость: SharedZoneOwner.isGuest)
    }

    /// Права как их задаёт карточка — до потолка гостя.
    private var своиПрава: Set<Permission> { customPermissions ?? role.defaultPermissions }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// Кто из участников — я, на **этом** телефоне.
    ///
    /// Поле `FamilyMember.isMe` для этого не годится и никогда не годилось:
    /// оно хранится в модели, а значит уезжает в общий дневник вместе
    /// с остальным. На втором телефоне «я» оказывалась карточка владельца,
    /// и человек видел чужую роль вместо своей.
    var myMemberID: UUID? {
        didSet { UserDefaults.standard.set(myMemberID?.uuidString, forKey: Keys.myMember) }
    }

    /// Взять свою роль и права из списка семьи.
    ///
    /// Зовётся при запуске. Раньше `adopt` вызывался ровно в одном месте —
    /// при ручной правке карточки, — поэтому на любом телефоне, где
    /// карточку не открывали, роль оставалась `.owner` по умолчанию:
    /// выданные права не применялись нигде.
    ///
    /// Если себя опознать не удалось в **чужом** дневнике — права
    /// наблюдателя. Прежняя редакция говорила «роль не трогаем вовсе»,
    /// и это было правдой по букве и неправдой по делу: не тронутая
    /// роль равнялась `.owner`, то есть запасной путь выдавал не
    /// «никаких прав», а **все**.
    func adoptMe(from members: [FamilyMember],
                 гость: Bool = SharedZoneOwner.isGuest) {
        if let мой = FamilyResolver.меня(среди: members, запомненный: myMemberID, гость: гость) {
            myMemberID = мой.id
            adopt(мой)
            return
        }

        // Себя опознать не удалось. Что это значит — зависит от того,
        // чей это дневник, и разница здесь ценой в дозу.
        //
        // **Свой дневник.** Участники — карточки, которые завёл сам
        // хозяин; себя среди них он мог и не заводить. Отнять у него
        // права значило бы запереть человека в собственном дневнике:
        // он не смог бы записать даже выход.
        //
        // **Чужой дневник** (приглашение принято, зона не наша).
        // Здесь неопознанность — это именно то, чем она выглядит:
        // мы не знаем, кто за телефоном, и выдавать всё нельзя.
        // Остаётся самое узкое: читать можно, писать нельзя.
        role = FamilyResolver.рольБезОпознания(гость: гость)
        if гость {
            StartupLog.note("себя в списке семьи не нашли — права наблюдателя")
        }
    }

    /// Состояние «человек на своём телефоне, семья ещё не заведена».
    ///
    /// Заведено ради тестов, но **не тестовая заглушка**: внутри тот же
    /// `adoptMe`, которым приложение пользуется при запуске. Разница
    /// с `AppState()` в том, что этот путь **пройден**, а не пропущен.
    ///
    /// Понадобилось, когда роль по умолчанию стала самой узкой:
    /// девять тестов писали в дневник из свежего `AppState()` и упёрлись
    /// в право. Дописать каждому `role = .owner` значило бы вернуть
    /// ровно тот приём, из-за которого дефект и жил — тест, ставящий
    /// руками состояние, которого у живого приложения не бывает.
    static func наСвоёмТелефоне() -> AppState {
        let состояние = AppState()
        состояние.adoptMe(from: [], гость: false)
        return состояние
    }

    /// Подтянуть права текущего человека из карточки участника.
    func adopt(_ member: FamilyMember) {
        role = member.role
        customPermissions = member.hasCustomPermissions ? member.permissions : nil
        // Имя тоже: без него все записи в семье подписаны одним человеком,
        // и «кто дал дозу» перестаёт быть вопросом с ответом.
        currentUserName = member.name
    }

    /// Кто сейчас за рулём: подставляется в автора записи.
    ///
    /// Хранится на телефоне, потому что записывать можно и не открывая
    /// приложение — голосом, кнопкой «Действие», с живой активности.
    var currentUserName: String = AppState.storedUserName {
        didSet { UserDefaults.standard.set(currentUserName, forKey: Keys.userName) }
    }

    /// Имя для тех, кто пишет в дневник без экранов.
    ///
    /// По умолчанию — «Я», а не имя владелицы: зашитая «Виктория»
    /// подписывала её именем записи, сделанные на чужом телефоне,
    /// и «кто дал дозу» переставало быть вопросом с ответом.
    static var storedUserName: String {
        UserDefaults.standard.string(forKey: Keys.userName) ?? String(localized: "Я")
    }

    /// Активный эпизод: 2+ инцидента за 24 часа.
    ///
    /// Держится в состоянии, но истина — в базе: раньше эпизод жил только
    /// в памяти, то есть внутри сеанса не заканчивался никогда, а после
    /// перезапуска исчезал. Теперь подтягивается при открытии экрана.
    var activeEpisode: Episode?

    /// Подтянуть эпизод из базы и убрать тот, что уже прошёл.
    func refreshEpisode(from episodes: [Episode], at now: Date = Date()) {
        activeEpisode = episodes
            .filter { $0.isActive(at: now) }
            .max { $0.lastIncidentAt < $1.lastIncidentAt }
    }
    /// Идущий выход или прогулка. Одновременно идёт что-то одно:
    /// выход — это короткий поход по нужде, прогулка — долгая, с отметками.
    ///
    /// Сохраняется на диск при каждом изменении: телефон лежит в кармане
    /// полчаса, система вправе выгрузить приложение, и прогулка не должна
    /// от этого пропадать.
    var session: ActiveSession? {
        didSet { ActiveSessionStore.save(session) }
    }

    /// Просмотр онбординга «как у нового человека».
    ///
    /// Настоящие шесть шагов вместо трёх, запись в базу выключена,
    /// флаг прохождения не трогается. Нужен двоим: человеку — сверить
    /// макет с экраном, стенду — снять кадр.
    ///
    /// **Живёт здесь, а не в `Settings`, и это не вкусовщина.**
    /// `Settings` пишет каждое своё поле в `UserDefaults`. Переживи
    /// просмотр перезапуск — человек оказался бы заперт в онбординге
    /// на собственном телефоне, и выйти было бы нечем: кнопка, которой
    /// он туда вошёл, лежит за онбордингом.
    var просмотрОнбординга: Bool

    init() {
        // Читается один раз и здесь: дальше состоянием владеет
        // приложение, и `finish()` онбординга его гасит. Будь это
        // вычисляемым от аргумента, просмотр нельзя было бы закончить —
        // аргумент процесса не меняется.
        просмотрОнбординга = TogoApp.просмотрОнбординга
        activeDogID = UserDefaults.standard.string(forKey: Keys.activeDog).flatMap(UUID.init)
        myMemberID = UserDefaults.standard.string(forKey: Keys.myMember).flatMap(UUID.init)
        session = ActiveSessionStore.load()
        // Прогулку могли забыть: приложение сняли из многозадачности,
        // сессия протухла через восемь часов — а на экране блокировки
        // всё ещё «гуляем», и новая прогулка осталась бы без активности.
        if session == nil {
            Task { await LiveActivityController.discardStale() }
        }
    }

    /// Тост отмены: каждая запись отменяется, удаление обратимо 5 секунд.
    var undo: UndoToast?

    var isEpisodeActive: Bool { activeEpisode?.isActive() ?? false }

    // MARK: Какая собака открыта

    /// У кого сегодня смотрим день.
    ///
    /// Модель с самого начала держала несколько собак — связи, бэкап
    /// и права написаны на многих, — но экраны брали `dogs.first`,
    /// то есть вторую собаку было некуда девать. Выбор живёт здесь,
    /// а не в базе: это состояние телефона, а не свойство собаки.
    /// У мамы на её телефоне может быть открыт другой пёс.
    var activeDogID: UUID? {
        didSet { UserDefaults.standard.set(activeDogID?.uuidString, forKey: Keys.activeDog) }
    }

    /// Кого показывать из тех, что есть.
    ///
    /// Если выбранная собака удалена или выбора ещё не было, берётся
    /// первая: экран не должен оставаться пустым из-за настройки.
    /// **Фильтр здесь — самое важное место скрытия.** Если безымянная
    /// запись окажется активной, человек получит пустой профиль
    /// и решит, что потерял собаку: экран не скажет «запись неполная»,
    /// он просто ничего не покажет. Выбор падает на `first`, а порядок
    /// `@Query` без сортировки нам не принадлежит, — то есть это не
    /// редкий случай, а лотерея.
    ///
    /// Фильтр один на весь показ: `shownToPerson` рядом с правилом
    /// в `Dog.swift`.
    func activeDog(from dogs: [Dog]) -> Dog? {
        let показываемые = dogs.shownToPerson
        return показываемые.first { $0.id == activeDogID } ?? показываемые.first
    }

    /// Переключиться на другую собаку.
    func select(_ dog: Dog) {
        guard activeDogID != dog.id else { return }
        activeDogID = dog.id
        Haptics.tap()
    }

    enum Keys {
        static let activeDog = "active.dog"
        static let userName = "current.user"
        /// Своя карточка участника. Лежит на телефоне, а не в модели:
        /// в модели она уехала бы в общий дневник ко всем сразу.
        static let myMember = "family.me"
    }

    struct UndoToast: Identifiable, Equatable {
        /// Что именно отменяет кнопка.
        ///
        /// Раньше тост знал только `eventID`, и отмена всегда означала
        /// «удалить эту запись». Для только что созданной записи это верно,
        /// а для удалённой — ровно наоборот: «Отменить» должно её вернуть.
        /// Поэтому у удаления `eventID` просто не проставляли, и кнопка
        /// не делала ничего — хотя рядом было написано, что удаление
        /// обратимо пять секунд.
        enum Action: Equatable {
            /// Убрать только что созданную запись.
            case removeCreated(UUID)
            /// Вернуть удалённые: прогулку и всё, что в ней отмечено.
            case restoreDeleted([UUID])
        }

        /// Получилось или нет. Знак на плашке берётся отсюда, а не из
        /// `action`: `action` отвечает на «есть ли что отменять», а это
        /// другой вопрос — «сработало ли».
        ///
        /// Заведено 09.10.2026 по замеру: двадцать восемь сообщений
        /// об отказе показывались с зелёной галочкой `checkmark.circle.fill`.
        /// Приложение при этом **знало** про отказ — ставило
        /// `Haptics.warning()` строкой выше во всех двадцати восьми, —
        /// и до плашки это знание не доезжало.
        ///
        /// > Направление у нас не передаётся значком, только словом.
        /// > Здесь была обратная ошибка: слово верное, а значок говорил
        /// > противоположное — и говорил громче, потому что глаз берёт
        /// > его раньше фразы.
        ///
        /// Умолчание — `.успех`: его ставят сорок три вызова из
        /// пятидесяти одного, и менять их смысл молча нельзя.
        /// Отказ называют явно, через `showFailure`.
        enum Tone: Equatable {
            case успех
            case отказ
        }

        let id = UUID()
        var message: String
        var action: Action?
        var tone: Tone = .успех
    }

    // MARK: Идущая сессия

    var isWalking: Bool { session?.kind == .walk }
    var walkStartedAt: Date? { session?.startedAt }
    var walkStartedBy: String? { session?.startedBy }

    func startOuting(by name: String, at date: Date = Date()) {
        session = ActiveSession(kind: .outing, startedAt: date, startedBy: name)
        UsageLog.note(.start, ActiveSession.Kind.outing.rawValue)
    }

    func startWalk(by name: String, at date: Date = Date()) {
        session = ActiveSession(kind: .walk, startedAt: date, startedBy: name)
        UsageLog.note(.start, ActiveSession.Kind.walk.rawValue)
    }

    /// Отметить, что собака что-то сделала прямо сейчас.
    func mark(_ kind: ActiveSession.Mark.Kind, at date: Date = Date()) {
        session?.marks.append(ActiveSession.Mark(kind: kind, at: date))
        UsageLog.note(.mark, kind.rawValue)
    }

    /// Перечитать прогулку с диска.
    ///
    /// Пока приложение было в фоне, отметку могли поставить с экрана
    /// блокировки — кнопкой на живой активности. Копия в памяти об этом
    /// не знает, и первое же изменение затёрло бы её.
    func reloadSession() {
        guard let stored = ActiveSessionStore.load() else {
            if session != nil { session = nil }
            return
        }
        if stored != session { session = stored }
    }

    /// Снять все отметки одного вида. Нужно для тех, что ставятся один раз
    /// за прогулку: повторный тап по ним — это «нет, всё-таки не было».
    func removeMarks(of kind: ActiveSession.Mark.Kind) {
        session?.marks.removeAll { $0.kind == kind }
        UsageLog.note(.mark, kind.rawValue, outcome: .cancelled)
    }

    func pauseSession() {
        session?.pause()
        UsageLog.note(.pause)
    }

    func resumeSession() {
        session?.resume()
        UsageLog.note(.resume)
    }

    /// Убрать последнюю отметку: на морозе одной рукой промахнуться легко.
    @discardableResult
    func undoLastMark() -> ActiveSession.Mark? {
        guard session?.marks.isEmpty == false else { return nil }
        let removed = session?.marks.removeLast()
        UsageLog.note(.mark, removed?.kind.rawValue, outcome: .cancelled)
        return removed
    }

    @discardableResult
    func finishSession() -> ActiveSession? {
        defer { session = nil }
        // Закрывать нечего — и отмечать нечего: пустой «закончил» в журнале
        // выглядел бы прогулкой, которой не было.
        guard let session else { return nil }
        UsageLog.note(.finish, session.kind.rawValue)
        return session
    }

    /// Совместимость со старым кодом выхода: возвращает длительность.
    @discardableResult
    func stopWalk() -> TimeInterval {
        guard let finished = finishSession() else { return 0 }
        return Date().timeIntervalSince(finished.startedAt)
    }

    /// Подтверждение записи. Показывается всегда, когда что-то записано:
    /// человек должен видеть, что тап сработал, — и иметь возможность
    /// тут же его отменить.
    func showUndo(_ message: String, eventID: UUID? = nil) {
        show(message, action: eventID.map(UndoToast.Action.removeCreated))
    }

    /// Тост об удалении: кнопка возвращает записи на место.
    func showUndoRestore(_ message: String, eventIDs: [UUID]) {
        show(message, action: .restoreDeleted(eventIDs))
    }

    /// Отказ: не сработало. Отменять нечего, и знак не должен обещать
    /// обратное.
    ///
    /// Заводится отдельным именем, а не флагом у `showUndo`, нарочно:
    /// у вызывающего и так есть эта развилка — он ставит
    /// `Haptics.warning()` вместо `Haptics.tap()`. Отдельное имя делает
    /// её видимой в коде, а не выводимой из четвёртого аргумента.
    /// Плашка отказа.
    ///
    /// `action` появился 09.10.2026 вместе с запретом строить `UndoToast`
    /// руками. Он нужен ровно одному месту — провалившейся отмене
    /// (`RootView`): там действие у плашки уже есть, и единственное,
    /// что было неверно, — знак. Без этого параметра у того места
    /// оставался выбор между «потерять кнопку» и «строить плашку мимо
    /// обеих функций», а второе и было дефектом.
    ///
    /// Умолчание `nil` оставляет все прежние вызовы какими были:
    /// отказ без действия — обычный случай, отказ с действием —
    /// исключение, и оно называется в месте вызова.
    func showFailure(_ message: String, action: UndoToast.Action? = nil) {
        show(message, action: action, tone: .отказ)
    }

    private func show(_ message: String, action: UndoToast.Action?,
                      tone: UndoToast.Tone = .успех) {
        withAnimation(.spring(duration: 0.28)) {
            undo = UndoToast(message: message, action: action, tone: tone)
        }
    }
}

/// Пользовательские настройки. Ничего из этого не уходит с телефона.
@Observable
final class Settings {
    /// Один пуш в выбранный час. Прерывают только доза и окно натощак.
    var briefHour: Int {
        didSet {
            UserDefaults.standard.set(briefHour, forKey: Keys.briefHour)
            UsageLog.note(.setting, "briefHour", on: .settings)
        }
    }
    var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }
    var lastSeenVersion: String {
        didSet { UserDefaults.standard.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }
    var notificationsAsked: Bool {
        didSet { UserDefaults.standard.set(notificationsAsked, forKey: Keys.notificationsAsked) }
    }
    /// Показывали ли мы своё окно про уведомления хоть раз.
    ///
    /// **Отдельно от `notificationsAsked`, и это не дубль.** Старый флаг
    /// значит «шаг онбординга пройден» — он встаёт и когда человек нажал
    /// «Не сейчас», не дойдя ни до какого окна. Правило же нового
    /// дизайна («спрашиваем в момент первой дозы, после отказа больше
    /// не спрашиваем») различает эти два случая, и сложить их в один
    /// флаг значит потерять запрет.
    var notificationsPrimed: Bool {
        didSet { UserDefaults.standard.set(notificationsPrimed, forKey: Keys.notificationsPrimed) }
    }
    /// Отказался ли человек у НАС, а не в системе.
    ///
    /// Системный отказ приходит из `UNUserNotificationCenter` и живёт
    /// в системе; этот — наш, и переживает переустановку разрешений.
    /// Спрашивать оба и хранить один значило бы проверять одну
    /// реализацию наблюдениями за другой.
    var notificationsDeclined: Bool {
        didSet { UserDefaults.standard.set(notificationsDeclined, forKey: Keys.notificationsDeclined) }
    }

    /// Память правила в том виде, в каком её ждёт домен.
    ///
    /// Собирается здесь, а не во вью: правило живёт в
    /// `NotificationPriming`, хранение — в настройках, и между ними
    /// нужен один мост, а не по мосту на каждый экран. У Togo уже было
    /// правило в трёх реализациях, и две молчали.
    var primingMemory: NotificationPriming.Memory {
        get { .init(didPrime: notificationsPrimed, didDecline: notificationsDeclined) }
        set {
            notificationsPrimed = newValue.didPrime
            notificationsDeclined = newValue.didDecline
        }
    }
    var quietHoursStart: Int {
        didSet {
            UserDefaults.standard.set(quietHoursStart, forKey: Keys.quietHoursStart)
            UsageLog.note(.setting, "quietHoursStart", on: .settings)
        }
    }
    var quietHoursEnd: Int {
        didSet {
            UserDefaults.standard.set(quietHoursEnd, forKey: Keys.quietHoursEnd)
            UsageLog.note(.setting, "quietHoursEnd", on: .settings)
        }
    }
    var haptics: Bool {
        didSet {
            UserDefaults.standard.set(haptics, forKey: Keys.haptics)
            UsageLog.note(.setting, "haptics", on: .settings)
        }
    }
    /// Язык интерфейса. Пусто — как в системе.
    ///
    /// iOS применяет `AppleLanguages` при следующем запуске: на лету
    /// перерисовать всё приложение нельзя, и притворяться, что можно,
    /// хуже, чем сказать прямо.
    var preferredLanguage: String {
        didSet {
            if preferredLanguage.isEmpty {
                UserDefaults.standard.removeObject(forKey: Keys.appleLanguages)
            } else {
                UserDefaults.standard.set([preferredLanguage], forKey: Keys.appleLanguages)
            }
            UserDefaults.standard.set(preferredLanguage, forKey: Keys.preferredLanguage)
        }
    }

    enum Keys {
        static let briefHour = "settings.briefHour"
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let lastSeenVersion = "settings.lastSeenVersion"
        static let notificationsAsked = "settings.notificationsAsked"
        static let notificationsPrimed = "settings.notificationsPrimed"
        static let notificationsDeclined = "settings.notificationsDeclined"
        static let quietHoursStart = "settings.quietHoursStart"
        static let quietHoursEnd = "settings.quietHoursEnd"
        static let haptics = "settings.haptics"
        static let preferredLanguage = "settings.preferredLanguage"
        static let appleLanguages = "AppleLanguages"
    }

    init(defaults: UserDefaults = .standard) {
        briefHour = defaults.object(forKey: Keys.briefHour) as? Int ?? 8
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) ?? ""
        notificationsAsked = defaults.bool(forKey: Keys.notificationsAsked)
        notificationsPrimed = defaults.bool(forKey: Keys.notificationsPrimed)
        notificationsDeclined = defaults.bool(forKey: Keys.notificationsDeclined)
        quietHoursStart = defaults.object(forKey: Keys.quietHoursStart) as? Int ?? 23
        quietHoursEnd = defaults.object(forKey: Keys.quietHoursEnd) as? Int ?? 7
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        preferredLanguage = defaults.string(forKey: Keys.preferredLanguage) ?? ""
    }

    /// Языки, которые приложение ПРЕДЛАГАЕТ ВЫБРАТЬ.
    ///
    /// Повторы убираются здесь, а не только в Info.plist: список идёт
    /// в `ForEach(id: \.self)`, и два одинаковых кода — это два
    /// одинаковых ряда и неопределённое поведение списка. Источник
    /// повтора может вернуться (Base, вариант языка, чужой ключ),
    /// а экран обязан остаться правдивым.
    ///
    /// **С 15.10.2026 предлагается только русский — решение Виктории,
    /// и у него есть механизм, который надо знать, иначе его отменят
    /// в третий раз.**
    ///
    /// Прежняя редакция брала список из бандла целиком с доводом «так
    /// в настройках не появится язык без перевода», а неполные языки
    /// помечались «перевод готовится» через `isTranslated`. Довод был
    /// верен, пока у `en` в бандле лежал один файл от извлечения
    /// AppIntents. Замер 15.10.2026:
    ///
    /// ```
    /// en.lproj в бандле      3 файла · Localizable.strings 287 786 Б
    ///                        2175 ключей
    /// щуп isTranslated       «Просится» → en 'Needs to go out?'
    ///                        fr 'Envie de sortir ?' · uk 'Проситься'
    ///                        → true У ВСЕХ ТРЁХ
    /// ключей без en/fr/uk    313 из 2522
    /// ```
    ///
    /// > **Пометка «перевод готовится» исчезла САМА, в момент успеха.**
    /// > Завезли каталог — щуп стал попадать, и приложение молча начало
    /// > предлагать три языка как готовые. Решения такого не принимал
    /// > никто: условие было привязано к содержимому бандла, содержимое
    /// > выросло, знак перевернулся.
    ///
    /// Поэтому отбор стоит на **списке решения**, а не на щупе: полный
    /// каталог сам по себе больше не основание предлагать язык.
    /// Увидев 2209 переведённых строк у французского, не возвращай его
    /// сюда — 313 ключей без перевода размазаны по экранам, и человек
    /// получит французский пополам с русским. Возвращает это её слово,
    /// а не замер каталога.
    ///
    /// **Цена названа вслух и принята:** французская ситтерша теряет
    /// и те 2209 строк, что уже переведены человеком. Переводы при этом
    /// остаются в каталоге и в бандле — убрано предложение выбрать
    /// язык, а не работа переводчика.
    ///
    /// **Граница, которую это НЕ закрывает:** `CFBundleLocalizations`
    /// у нас не задан, языки бандлу дают папки `.lproj`, и они на месте.
    /// Значит телефон с французской системой по-прежнему получит
    /// французский интерфейс сам, мимо этого экрана. Здесь убран наш
    /// ВЫБОР, а не способность iOS выбрать.
    static let предлагаемыеЯзыки: Set<String> = ["ru"]

    var availableLanguages: [String] {
        var seen = Set<String>()
        return Bundle.main.localizations
            .filter { $0 != "Base" && seen.insert($0).inserted }
            // Пересечение с бандлом, а не просто список решения: если
            // `ru.lproj` однажды не доедет, экран обязан показать это,
            // а не нарисовать русский из константы.
            .filter { Self.предлагаемыеЯзыки.contains($0) }
            .sorted()
    }

    /// Есть ли для языка настоящий перевод. Пока переведён только русский,
    /// и приложение об этом честно пишет.
    func isTranslated(_ code: String) -> Bool {
        guard code != "ru" else { return true }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return false }
        let probe = "Просится"
        return bundle.localizedString(forKey: probe, value: probe, table: nil) != probe
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// В тихие часы приложение не спрашивает результат выхода —
    /// собирает утром одной карточкой.
    func isQuietHour(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return quietHoursStart <= quietHoursEnd
            ? (hour >= quietHoursStart && hour < quietHoursEnd)
            : (hour >= quietHoursStart || hour < quietHoursEnd)
    }
}
