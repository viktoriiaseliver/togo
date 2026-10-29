import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Идущий выход. Live Activity с секундами видна всей семье — это единственный
/// способ не спрашивать «ты уже вывела?» в мессенджере.
///
/// Тип общий для приложения и виджета: он лежит в TogoShared, который входит
/// в оба таргета.
nonisolated struct WalkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Когда начали. Секунды считает система, а не приложение.
        public var startedAt: Date
        /// Результат уже отмечен — активность можно свернуть.
        public var outcome: String?
        /// Что успели отметить: «моча 2 · стул». Показывается прямо
        /// на заблокированном экране — иначе нажатие проходит вслепую.
        public var tally: String?

        public init(startedAt: Date, outcome: String? = nil, tally: String? = nil) {
            self.startedAt = startedAt
            self.outcome = outcome
            self.tally = tally
        }
    }

    public var dogName: String
    public var startedBy: String
    /// Кобель: кнопки «Пописал» на блокировке нет (решение Виктории
    /// 29.10.2026 — у кобеля выход сам и есть моча, `ToiletClock`).
    /// Опционально: активность, запущенная прежней сборкой, декодируется
    /// без этого поля и показывает обе кнопки, как показывала.
    public var кобель: Bool?

    public init(dogName: String, startedBy: String, кобель: Bool = false) {
        self.dogName = dogName
        self.startedBy = startedBy
        self.кобель = кобель
    }
}
#endif
