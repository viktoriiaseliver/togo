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

    public init(dogName: String, startedBy: String) {
        self.dogName = dogName
        self.startedBy = startedBy
    }
}
#endif
