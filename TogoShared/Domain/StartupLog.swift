import Foundation

/// Крошки запуска.
///
/// На телефоне без отладчика падение видно только как «signal 5» — без
/// строки и без причины. Поэтому приложение само отмечает, докуда дошло:
/// файл лежит в его папке документов, и его можно забрать с устройства
/// (`Tools/pull_startup_log.sh`) или увидеть в «Файлах».
///
/// Пишем только этапы старта и ошибки хранилища — ничего о собаке.
nonisolated enum StartupLog {
    private static let fileName = "startup.log"
    /// Больше десяти запусков хранить незачем.
    private static let keepLines = 200

    static var url: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appending(path: fileName)
    }

    static func note(_ message: String) {
        log.notice("старт: \(message, privacy: .public)")
        guard let url else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"

        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) ?? []
        lines.append(line.trimmingCharacters(in: .newlines))
        if lines.count > keepLines { lines.removeFirst(lines.count - keepLines) }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func read() -> String {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Записей нет."
        }
        return text
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
