import SwiftUI
import Observation

// Вынесено из `AppState.swift` 04.11.2026 целиком, без правок
// (пачка 6 `docs/аудит-рефакторинга-2026-11-04.md`): второй класс
// в файле состояния приложения прятал настройки за 600 строками
// ролей, сессии и тостов. Сторожа, читающие `AppState.swift`,
// `Settings` не касаются — проверено поиском по `TogoTests`.

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
    /// **С 23.10.2026 предлагаются все пять — решение Виктории.
    /// До этого здесь стоял один русский, и у смены знака есть адрес.**
    ///
    /// ```
    /// 15.10.2026  предлагается только русский        d409d32
    /// 19.10.2026  «Togo выпускается на русском»,     ~/Projects db281a7
    ///             три локали удалены из ASC          HTTP 204 у всех трёх
    /// 23.10.2026  «витрина должна быть на всех       3079cef
    ///             существующих языках»               локалей 1 → 4
    /// 23.10.2026  «казахский остаётся в приложении   81ba661
    ///             — как вариант для людей»           docs/вопросы-
    ///                                                дизайну-…-круг-5.md
    /// 23.10.2026  «несколько языков» — прямой ответ  ЭТА ПРАВКА
    ///             на вопрос, сколько предлагать
    /// ```
    ///
    /// **Адрес последнего разрешения, без которого правку снимут
    /// обратно и снимут правильно:** спрашивала сессия-менеджер
    /// (`fix-togo-language-list`), 23.10.2026 вечером, чат с Викторией;
    /// ответ — «несколько языков». **До меня он дошёл пересказом
    /// менеджера, а не от неё напрямую** — и по своду это не её слово.
    /// Поэтому правка стоит не на нём: она стоит на `3079cef`
    /// и `81ba661`, где то же решение лежит в git с замерами. Пересказ
    /// записан как совпавший с ними, а не как основание.
    ///
    /// > **Сверка разрешений пойдёт по прежней записи** —
    /// > `Дизайн/кадры-приёмки/витрина-редизайн-23.10/ПОДПИСИ.md`
    /// > говорила обратное («в списке один язык — это верно»). Там
    /// > она зачёркнута с разбором: написана в 17:46, посылку Виктория
    /// > сняла в 16:13. Не устарела — разминулась.
    ///
    /// > **Посылкой `["ru"]` была версия 1.0 на одном русском, и эта
    /// > посылка снята 23.10 в 16:13 — тем же человеком, который её
    /// > поставил.** Константа осталась последним местом, где ещё
    /// > исполнялось решение от 19.10: витрина у Apple уже говорила
    /// > на четырёх языках, каталог — на пяти, а экран «Язык» показывал
    /// > человеку одну строку. Наряд не перечитывают, наряд выполняют.
    ///
    /// **Чего это решение НЕ отменяет — щуп по-прежнему не основание.**
    /// Прежняя редакция брала список из бандла целиком, а неполные
    /// языки помечала «перевод готовится» через `isTranslated`. Замер
    /// 15.10.2026:
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
    /// Поэтому отбор так и стоит на **списке решения**, а не на щупе:
    /// пять имён тут лежат потому, что их назвала Виктория, а не потому,
    /// что каталог полон. Убавить и прибавить язык — тоже её слово.
    ///
    /// **Граница, которую это НЕ закрывает — и число у неё своё.**
    /// В `3079cef` (23.10, 16:13) записано «91 ключ без словаря
    /// локализаций, 68 из них кириллическая проза». **Это число
    /// устарело за час** — `bf7e217` в 17:01 перевёл 72 ключа.
    /// Замер по дереву на `1f282c5`, 23.10 вечером:
    ///
    /// ```
    /// ключей в каталоге                3479
    /// без локализаций ВОВСЕ              22   ← было 91
    ///   из них пользовательской прозы     0
    ///   остальное: '', ' · ', '%lld %@', 'Togo Pro', 'Lévothyrox',
    ///   числа образцов и четыре АРГУМЕНТА ЗАПУСКА («-Онбординг»,
    ///   «-Сценарий», «-ИсходПриёма», «-ЧужаяЗона») — кириллица
    ///   в них есть, читателя-человека нет
    /// нет en / fr / uk                   30 = 22 + 8
    ///   те 8: '%@ %@', '<', '=', '>', '12,9', '51,5', '66', '8935331'
    /// нет kk                             22 — ровно те же, без восьми
    /// ```
    ///
    /// > **Я взял 91 из сообщения коммита и не померил — число успело
    /// > умереть в тот же день.** «Число, на котором стоит запись,
    /// > проверяется прежде записи», и здесь оно проверено не было.
    /// > Считать из каталога, а не отсюда: эта копия разойдётся так же.
    ///
    /// **И вторая:** `CFBundleLocalizations` у нас не задан, языки
    /// бандлу дают папки `.lproj`. Эта константа решает, что предлагает
    /// НАШ экран; способность iOS выбрать язык системой она не трогает
    /// ни в одну сторону.
    static let предлагаемыеЯзыки: Set<String> = ["ru", "en", "fr", "uk", "kk"]

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

    /// Есть ли для языка настоящий перевод.
    ///
    /// **Щуп, а не приёмка.** Спрашивает у бандла одну строку
    /// («Просится») и отвечает «переведён», если она не вернулась собой.
    /// На 23.10.2026 попадает у всех пяти языков — то есть пометки
    /// «перевод готовится» не получает никто, и это ничего не говорит
    /// о полноте: 91 ключ каталога вообще без локализаций (`3079cef`).
    /// Разбор того, как эта пометка исчезла сама, — у `предлагаемыеЯзыки`.
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
