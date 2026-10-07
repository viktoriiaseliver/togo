import Foundation

/// Срез для виджетов и локскрина.
///
/// Виджет не лезет в базу: приложение кладёт в общее хранилище маленький
/// снимок, а виджет его читает. Так виджет не зависит от схемы SwiftData
/// и не может подвиснуть на миграции.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var dogName: String
    var dogInitial: String
    /// Текст вердикта «просится» — уже посчитанный, без логики на стороне виджета.
    var verdictTitle: String
    var verdictBadge: String
    var sinceUrineSeconds: Double?
    /// Дата, с которой про мочу нечего сказать, — если `UrineSilence`
    /// так решил. Не пусто ⇒ виджет печатает дату, а число не печатает
    /// вовсе, каким бы оно ни было.
    ///
    /// **Решение приезжает готовым нарочно.** Виджету хватило бы
    /// `sinceUrineSeconds`, чтобы сравнить с сутками самому, — и это
    /// ровно тот дефект, на котором Togo уже обжигался: окно «не кормить»
    /// виджет считал собственной арифметикой и молчал в двух случаях
    /// из трёх, пока главный экран знал правило. Сторож на вызов такого
    /// не видит: звать нечего.
    var urineSilenceSince: Date?
    var lastStoolSummary: String?
    var lastWalkSummary: String?
    var walkStartedAt: Date?
    var walkStartedBy: String?
    var fastingEndsAt: Date?

    /// Еда: когда в последний раз и сколько из запланированного.
    ///
    /// Замер 23.09.2026 по журналу с телефона: пять сессий из
    /// четырнадцати начинаются с записи еды, и еда — самое частое
    /// действие вообще. Приложение открывают, чтобы покормить,
    /// а виджет об этом не говорил ничего.
    var lastMealAt: Date?
    var mealsToday: Int
    var mealsPlanned: Int

    var updatedAt: Date

    /// Заглушка виджета — **её человек видит**, а не только мы.
    ///
    /// `TodayWidget.swift:25` отдаёт её из `placeholder(in:)`: это
    /// и галерея при добавлении виджета, и то, что стоит на экране,
    /// пока снимок не прочитан.
    ///
    /// **Три слова здесь рисовались по-русски на любом языке.** Литерал
    /// в `String`-поле — это ЗНАЧЕНИЕ, и до каталога оно не доходит;
    /// `Text(значение)` печатает его дословно. Тот же класс, что
    /// `dog?.name ?? "Собака"` на тридцати поверхностях, только здесь
    /// не про пустоту, а про язык.
    ///
    /// Новых ключей это не заводит: «Собака», «Просится» и «нет данных»
    /// лежат в каталоге на всех четырёх языках. Слова не меняются —
    /// текст заморожен решением Виктории 07.10.2026; меняется только
    /// дорога, которой они идут на экран.
    static let empty = WidgetSnapshot(
        dogName: String(localized: "Собака"),
        dogInitial: "?",
        verdictTitle: String(localized: "Просится"),
        verdictBadge: String(localized: "нет данных"),
        sinceUrineSeconds: nil,
        urineSilenceSince: nil,
        lastStoolSummary: nil,
        lastWalkSummary: nil,
        walkStartedAt: nil,
        walkStartedBy: nil,
        fastingEndsAt: nil,
        lastMealAt: nil,
        mealsToday: 0,
        mealsPlanned: 0,
        updatedAt: .distantPast
    )
}

/// Мост между приложением и виджетами. Одно место записи и одно чтения.
nonisolated enum WidgetBridge {
    static let key = "widget.snapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    static func publish(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
