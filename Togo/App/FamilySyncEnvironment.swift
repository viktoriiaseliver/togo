import SwiftUI

/// Обмен виден экранам через окружение — как и всё остальное общее.
/// Может отсутствовать: пока общий дневник выключен, его просто нет.
private struct FamilySyncKey: EnvironmentKey {
    static let defaultValue: FamilySync? = nil
}

extension EnvironmentValues {
    var familySync: FamilySync? {
        get { self[FamilySyncKey.self] }
        set { self[FamilySyncKey.self] = newValue }
    }
}
