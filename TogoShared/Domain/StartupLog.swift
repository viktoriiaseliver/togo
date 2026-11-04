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
    private static let замок = NSLock()
    /// `ISO8601DateFormatter` потокобезопасен (документация Apple), поэтому
    /// один на процесс, а не новый на каждую строку журнала.
    nonisolated(unsafe) private static let отметка = ISO8601DateFormatter()

    static var url: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appending(path: fileName)
    }

    /// Записать строку.
    ///
    /// **Дописываем, а не перезаписываем — и это починка, а не стиль.**
    ///
    /// До 28.09 здесь стояло «прочитать весь файл, добавить строку,
    /// записать целиком». Два писателя разом — приложение и расширение
    /// виджета, или две задачи внутри приложения — читают одно и то же
    /// содержимое, каждый дописывает СВОЮ строку, и последний, кто
    /// записал, стирает чужую.
    ///
    /// Цена была заплачена в тот же день. 28.09 в журнале с телефона
    /// нашлась строка «собака 4204D534 — исчезла», и по ней собирались
    /// искать потерю данных. Разбор показал другое: в 13:23:49 за 24.09
    /// одна собака объявлена приехавшей при счётчике «одна», а двух
    /// строк «исчезла», которые обязаны были стоять рядом, **нет**.
    /// Они были написаны и затёрты.
    ///
    /// > **По отсутствию строки в таком журнале вывода сделать нельзя.**
    /// > Инструмент не падает и не молчит — он отвечает неполной
    /// > правдой, а читается как полная.
    ///
    /// Теперь строка уходит одним `write` в дескриптор, открытый
    /// с `O_APPEND`: ядро само ставит её в конец, и записи меньше
    /// `PIPE_BUF` не переплетаются. Это не блокировка — это отсутствие
    /// состояния, которое можно потерять.
    static func note(_ message: String) {
        log.notice("старт: \(message, privacy: .public)")
        guard let url else { return }
        let stamp = Self.отметка.string(from: Date())
        // Дописать и подрезать — одним куском (04.11.2026): `note` зовут
        // из открытия хранилища на любом потоке, и две записи разом
        // теряли строку — подрезка одной читала файл до дописи другой
        // и заменяла его целиком.
        замок.lock(); defer { замок.unlock() }
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }

        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        _ = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress, buf.count)
        }
        close(fd)

        подрезать(url)
    }

    /// Обрезать хвост, когда файл разросся.
    ///
    /// Здесь чтение-запись целиком остаётся, и это **названная дыра**:
    /// подрезка может затереть строку, пришедшую в ту же миллисекунду.
    /// Но случается она в полтора раза реже предела, а не на каждой
    /// строке, — то есть окно потери из «всегда» стало «изредка».
    /// Закрыть до нуля можно только внешней блокировкой, и она
    /// обойдётся дороже того, что стережёт.
    private static func подрезать(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > keepLines * 3 / 2 else { return }
        lines.removeFirst(lines.count - keepLines)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func read() -> String {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "Записей нет.")
        }
        return text
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
