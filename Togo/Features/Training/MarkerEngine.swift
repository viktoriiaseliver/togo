import Foundation

/// Секундомер занятия и подсчёт задержек маркера.
///
/// Единственная ценная вещь, которую приложение может дать в момент занятия, —
/// обратная связь по задержке. Не количество кусочков: собака учится от того,
/// что маркер приходит в течение полусекунды после нужного действия.
@Observable
final class MarkerSession {
    /// Длина занятия — ограничение, а не подсказка. Задаётся в профиле
    /// собаки (2–5 минут, `Dog.sessionLengthMinutes`), по умолчанию три.
    /// Тексты экрана берут её отсюда, а не пишут «три минуты» словами:
    /// до 20.10.2026 при пяти минутах экран говорил «Три минуты прошли»
    /// не вовремя.
    let limitSeconds: Int

    var limitMinutes: Int { limitSeconds / 60 }

    private(set) var startedAt: Date?
    private(set) var actionAt: Date?
    private(set) var delaysMs: [Int] = []
    private(set) var successes = 0
    private(set) var attempts = 0

    var observations: Set<SessionObservation> = []

    init(limitMinutes: Int = 3) {
        self.limitSeconds = limitMinutes * 60
    }

    var isRunning: Bool { startedAt != nil }

    /// Ждём маркер: собака уже сделала то, что мы отмечаем.
    var isWaitingForMark: Bool { actionAt != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, Double(limitSeconds) - elapsed(at: now))
    }

    /// После заданной длины приложение перестаёт называть это занятием
    /// и не пишет прогресс: собака начинает угадывать, а не учиться.
    func isOvertime(at now: Date = Date()) -> Bool {
        elapsed(at: now) > Double(limitSeconds)
    }

    func hint(at now: Date = Date()) -> String {
        if !isRunning { return String(localized: "коротко — это правильно") }
        if isOvertime(at: now) { return String(localized: "время вышло — заканчивай на удачном повторе") }
        if isWaitingForMark { return String(localized: "маркируй прямо сейчас") }
        return String(localized: "норма 2–5 мин · дальше устаёт")
    }

    func start(at now: Date = Date()) {
        startedAt = now
        actionAt = nil
        delaysMs = []
        successes = 0
        attempts = 0
    }

    /// Первый тап: «он сделал».
    func markAction(at now: Date = Date()) {
        guard isRunning, actionAt == nil else { return }
        actionAt = now
        attempts += 1
    }

    /// Второй тап: маркер. Между ними и живёт вся точность.
    @discardableResult
    func markMarker(at now: Date = Date()) -> MarkAccuracy? {
        guard let actionAt else { return nil }
        let delay = Int((now.timeIntervalSince(actionAt) * 1000).rounded())
        delaysMs.append(delay)
        self.actionAt = nil
        let accuracy = MarkAccuracy.from(delayMilliseconds: delay)
        if accuracy == .onTime { successes += 1 }
        return accuracy
    }

    /// Повтор не получился: собака не сделала то, что просили.
    func markMiss() {
        guard isRunning else { return }
        attempts += 1
        actionAt = nil
    }

    func reset() {
        delaysMs = []
        successes = 0
        attempts = 0
        actionAt = nil
    }

    var lastAccuracy: MarkAccuracy? {
        delaysMs.last.map(MarkAccuracy.from(delayMilliseconds:))
    }

    var lastDelayMs: Int? { delaysMs.last }

    var onTimeCount: Int {
        delaysMs.filter { MarkAccuracy.from(delayMilliseconds: $0) == .onTime }.count
    }

    var averageDelayMs: Int {
        guard !delaysMs.isEmpty else { return 0 }
        return delaysMs.reduce(0, +) / delaysMs.count
    }

    /// Занятие не засчитывается, если собака не брала еду или мы вышли за три минуты.
    func countsTowardProgress(at now: Date = Date()) -> Bool {
        !isOvertime(at: now) && !observations.contains(where: \.stopsSession)
    }

    /// Сколько корма ушло. Граммы нужны в итоге, а не во время работы.
    func gramsUsed(perMarkGrams: Double = 0.5) -> Int {
        Int((Double(delaysMs.count) * perMarkGrams).rounded())
    }
}
