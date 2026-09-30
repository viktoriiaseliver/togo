import Foundation

extension AppState {
    /// Можно ли этому человеку править и удалять запись.
    ///
    /// Раньше экраны спрашивали только `can(.editRecords)`, а сводка роли
    /// «Ухаживающий» обещала «правка 24 ч» — срока не было нигде. Теперь
    /// право и срок роли проверяются одной функцией (`FamilyRole.mayEdit`).
    ///
    /// Возраст записи считается от момента, когда её **записали**
    /// (`enteredAt`), а у обычных записей, где это поле пусто, — от `date`:
    /// там они совпадают.
    func canEdit(_ event: LogEvent, at now: Date = Date()) -> Bool {
        role.mayEdit(recordedAt: event.enteredAt ?? event.date,
                     with: permissions, at: now)
    }
}
