import Testing
import Foundation

/// Правила навигации, которые легко сломать правкой вью.
///
/// Разбор — `docs/NAVIGATION.md`: вкладка → экран → форма. Экран,
/// на который ушли с вкладки, не должен показывать панель вкладок:
/// иначе у него два выхода с разным смыслом — «назад» возвращает,
/// а вкладка молча бросает начатое.
@Suite("Навигация")
struct NavigationTests {

    @Test("Настройки не показывают панель вкладок")
    func настройкиБезПанели() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Togo/Features/Settings/SettingsScreen.swift")
        let текст = try String(contentsOf: url, encoding: .utf8)
        #expect(текст.contains(".toolbar(.hidden, for: .tabBar)"), """
            на экране настроек снова видна панель вкладок.
            Настройки — не вкладка, а место, куда ушли с вкладки:
            два выхода с разным смыслом читаются как поломка.
            Разбор — docs/NAVIGATION.md.
            """)
    }
}
