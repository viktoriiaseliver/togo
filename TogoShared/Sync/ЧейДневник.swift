import Foundation

/// Имя того, кто позвал, — для человека, а не для обмена.
///
/// **До 29.10.2026 оно нигде не хранилось** (разбор у
/// `SharedDiaryScreen.statusCard`): `CKShare.Metadata` приносит его при
/// приёме, тост «Готово: ты в дневнике — Виктория» жил пять секунд,
/// и дальше гость видел только «Чей дневник: другого человека». Мама
/// не могла убедиться, что вошла туда, куда звали, — а это ровно
/// вопрос «получилось или нет», ради которого Виктория и написала.
///
/// `UserDefaults`, а не база: это подпись на этом телефоне, второму
/// человеку она не нужна, а `SharedZoneOwner.name` рядом живёт так же.
nonisolated enum ЧейДневник {
    private static let ключ = "sharedDiary.ownerDisplayName"

    static var имя: String? {
        get { UserDefaults.standard.string(forKey: ключ).flatMap { Fmt.notBlank($0) } }
        set { UserDefaults.standard.set(newValue, forKey: ключ) }
    }
}
