import Foundation
import CloudKit

/// Чей это дневник — свой или тот, в который позвали.
///
/// **Почему без этого обмен молчал в одну сторону.** Зона общего
/// дневника у владельца и у гостя одна и та же, но адресуется она
/// по-разному: `CKRecordZone.ID` состоит из имени зоны **и имени
/// владельца**. У владельца имя владельца — `CKCurrentUserDefaultName`,
/// и зона лежит в его личной базе. У гостя оно чужое, а сама зона
/// видна в общей базе. Пока имя бралось как `CKCurrentUserDefaultName`
/// у обоих, гость писал в собственную личную базу: отметки ложились
/// в зону, которой никто не делился и которую никто не читал. На вид
/// у гостя всё сохранялось, а до владельца не доезжало ничего.
///
/// Имя владельца известно ровно в один момент — когда приглашение
/// принято: оно лежит в `CKShare.Metadata`. Поэтому оно и хранится,
/// а не вычисляется заново.
nonisolated enum SharedZoneOwner {
    private static let key = "sharedDiary.ownerName"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Имя владельца зоны. `nil` — дневник наш собственный.
    ///
    /// `CKCurrentUserDefaultName` тоже значит «наш»: записывать его
    /// как чужого владельца нельзя, иначе свой же дневник уехал бы
    /// искать себя в общей базе.
    static var name: String? {
        get { defaults.string(forKey: key) }
        set {
            guard let newValue, !newValue.isEmpty, newValue != CKCurrentUserDefaultName else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(newValue, forKey: key)
        }
    }

    /// Мы в чужом дневнике.
    static var isGuest: Bool { name != nil }

    static func reset() { defaults.removeObject(forKey: key) }
}

/// Как зовут **вошедшего по приглашению** — то есть нас, на этом телефоне,
/// в чужом дневнике.
///
/// # Чем это оплачено: «система считает меня анонимом» (29.10.2026)
///
/// Замер того дня, контроль в той же команде:
///
/// ```
/// CKShare.currentUserParticipant   0 вхождений во всём дереве
/// контроль: share.participants    14 вхождений, rc=0 — запрос жив
/// currentUserName = …              ОДИН писатель: AppState.swift:201,
///                                  внутри adopt(_ member:)
/// FamilyMember(…)                  ни одного создания на приёме
///                                  приглашения
/// ```
///
/// Из трёх строк складывается одно: **приложение не спрашивало, кто
/// вошёл, ни одним способом.** `ShareAcceptance.accepted` запоминал
/// владельца зоны и включал обмен — и всё. Своей карточки у гостя нет
/// по построению (`FamilyResolver.меня(…, гость: true)` опознаёт только
/// по `myMemberID`, а его пишет онбординг владельца), значит `adopt(_:)`
/// не вызывается, значит имя остаётся `AppState.storedUserName` —
/// то есть «Я».
///
/// Человек входит в дневник, его записи подписаны словом «Я», в списке
/// доступа он «Без имени», роль — наблюдатель. Это и есть аноним:
/// не роль, а **отсутствие имени у того, кого CloudKit знает по имени.**
///
/// # Почему хранится, а не спрашивается у облака при показе
///
/// Имя приходит ровно в один момент — когда приглашение принято, вместе
/// с `CKShare.Metadata`. Тот же довод, что у `SharedZoneOwner` строкой
/// выше: спросить его заново неоткуда, а второй вход в подпись записей
/// (голос, кнопка «Действие», виджет) живёт в чужом процессе, где
/// ни `AppState`, ни сети может не быть вовсе.
///
/// # Группа приложений, а не `UserDefaults.standard`
///
/// Устроено как `SharedZoneOwner`, `НеудачаПриёма` и `НазначениеПоОбмену`
/// — тем же ключом в той же группе. Четвёртой формы хранения
/// не заводится, и ключ `AppState.Keys.userName` отсюда не трогается:
/// он живёт в таргете приложения, а этот файл собирается ещё
/// и в расширении.
nonisolated enum ИмяПоПриглашению {
    private static let key = "sharedDiary.myName"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Имя вошедшего, как его знает CloudKit. `nil` — не знаем.
    ///
    /// Пустую строку не хранит: CloudKit отдаёт `nameComponents`
    /// не всегда, и собранная из пустых частей строка — это «не знаем»,
    /// а не имя. Подставить сюда что-нибудь нельзя: имя уходит в автора
    /// записи, а «кто дал дозу» потом читает врач.
    static var имя: String? {
        get { defaults.string(forKey: key) }
        set {
            guard let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(newValue, forKey: key)
        }
    }

    static func reset() { defaults.removeObject(forKey: key) }
}

/// Куда уходят свои изменения.
///
/// Обе величины выведены из одного — имени владельца, — и выведены
/// здесь, а не на месте: разойтись зоне и базе нельзя. Запись в
/// правильную зону, но не в ту базу, CloudKit не примет, а запись
/// в свою базу под чужим именем зоны потеряется молча.
nonisolated enum SharedZoneRouting {

    static func zone(owner: String?) -> CKRecordZone.ID {
        SharedDiaryRecords.zoneID(owner: owner ?? CKCurrentUserDefaultName)
    }

    /// Гость пишет в общую базу: своей копии этой зоны у него нет вовсе.
    static func scope(owner: String?) -> CKDatabase.Scope {
        owner == nil ? .private : .shared
    }
}
