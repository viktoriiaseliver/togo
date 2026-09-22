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
