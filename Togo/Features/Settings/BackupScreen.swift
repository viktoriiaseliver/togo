import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Резервная копия дневника.
///
/// Дневник живёт на телефоне — значит, у человека должен быть способ забрать
/// его с собой: на новый телефон, после переустановки, просто «на всякий».
/// Файл обычный JSON: его видно глазами и он не привязан к нашему серверу,
/// которого нет.
///
/// # Экран называется «Копия», а не «Перенос» — слово дизайна 25.10.2026
///
/// `Дизайн/редизайн-ios28/ОТВЕТЫ-круг-5.md`, пункт 8, дословно: «Экран
/// про резервную копию, перенос — его следствие. Строки: iCloud · JSON
/// · CSV». Надзаголовок стоял верный с самого начала и не тронут;
/// менялись заголовок и `navigationTitle`.
///
/// **Новой строки это не заводит, и это замер, а не надежда.** Ключ
/// «Копия» уже лежит в `TogoShared/Resources/Localizable.xcstrings`
/// с переводами на `en` · `fr` · `kk` · `uk` (`extractionState:
/// manual`), то есть переименование не прибавляет долга перевода ни
/// на одну строку. Снятый ключ «Перенос» оставлен в каталоге: его
/// по-прежнему зовёт `UsageLog.swift:79` (имя экрана в журнале
/// действий).
struct BackupScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var events: [LogEvent]

    @State private var archive: BackupArchive?
    @State private var fileData: Data?
    @State private var isImporting = false
    @State private var pendingArchive: BackupArchive?
    @State private var strategy: BackupService.Strategy = .merge
    @State private var message: Message?
    @State private var cloud: Persistence.CloudState?
    @State private var isBuilding = true

    private struct Message: Identifiable {
        let id = UUID()
        let tone: TGTone
        let title: String
        let detail: String
    }

    var body: some View {
        TGScreen {
            // Заголовок — тот же ключ, что и у `navigationTitle`.
            // Новых строк шапка не заводит нарочно: каталог
            // `TogoShared/Resources/Localizable.xcstrings` сегодня
            // правит другая сессия (вычитка пяти языков), и каждый
            // новый литерал — её работа, а не моя.
            CinemaHeader("Копия", надпись: "iCloud · JSON · CSV", отступы: false)
            // Выгрузка выключена `.disabled(!appState.can(.exportData))`
            // (`:205`). Образец плашки стоял экраном левее
            // (`DataPrivacyScreen:35`) с самого начала — здесь его
            // не было. Новых строк это не заводит: заголовок и подпись
            // строит `ПлашкаПрава` из `Permission`.
            if !appState.can(.exportData) { ПлашкаПрава(право: .exportData) }
            iCloudCard
            exportCard
            csvCard
            importCard
            if let message { messageCard(message) }
            formatCard
        }
        .navigationTitle("Копия")
        // Фотографии под шапкой здесь НЕТ, и это не забывчивость:
        // `TGScreen` рисует свою непрозрачную подложку, сквозь неё фон
        // не виден. Пустить фото на эти экраны — значит править каркас
        // в `Togo/DesignSystem`, а там сегодня чужая работа. Названо
        // в отчёте открытым пунктом, а не сделано молча.
        .cinemaScreen()
        .usageScreen(.backup)
        .task {
            rebuild()
            isBuilding = false
            cloud = await Persistence.cloudState()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handle(result)
        }
        .confirmationDialog("Что сделать с тем, что уже есть?",
                            isPresented: Binding(get: { pendingArchive != nil },
                                                 set: { if !$0 { pendingArchive = nil } }),
                            titleVisibility: .visible) {
            ForEach(BackupService.Strategy.allCases, id: \.self) { option in
                Button(option.title, role: option == .replace ? .destructive : nil) {
                    restore(using: option)
                }
            }
            Button("Отмена", role: .cancel) { pendingArchive = nil }
        } message: {
            Text(pendingArchive.map {
                String(localized: "Файл сделан \(Fmt.shortDay($0.createdAt)), внутри: \($0.summary).")
            } ?? "")
        }
    }

    // MARK: iCloud

    private var iCloudCard: some View {
        TGCard {
            TGSectionHeader(title: "переустановка")
            if let cloud {
                HStack(alignment: .top, spacing: Token.Space.s12) {
                    Image(systemName: cloud.isGood ? "checkmark.icloud" : "icloud.slash")
                        .font(.system(size: Token.Size.iconLg, weight: .medium))
                        .foregroundStyle(cloud.isGood ? Token.Action.doneText : Token.Ink.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(cloud.title).textStyle(AppFont.bodyEmphasis)
                        Text(cloud.detail)
                            .textStyle(AppFont.caption)
                            .wraps()
                    }
                }
            } else {
                TGLoading(message: "Проверяю iCloud…", isCompact: true)
            }
            TGExplainer(text: "iCloud — это твоё хранилище, а не наше: у приложения нет серверов и нет доступа к твоим записям.")
        }
    }

    // MARK: Выгрузка

    private var exportCard: some View {
        TGCard {
            TGSectionHeader(title: "сохранить файл",
                            subtitle: archive.map { .готовая($0.summary) } ?? "считаю…")
            if isBuilding {
                TGLoading(message: "Собираю файл из дневника…", isCompact: true)
            } else if let fileData, archive != nil {
                ShareLink(
                    item: BackupFile(name: BackupService.fileName(), data: fileData),
                    preview: SharePreview("Дневник Togo")
                ) {
                    TGListRow(title: "Сохранить дневник в файл",
                              value: .готовая(sizeText(fileData)),
                              systemImage: "square.and.arrow.up",
                              accessory: .none)
                }
                .buttonStyle(.plain)
            } else {
                TGExplainer(text: "Пока нечего сохранять: заведи собаку и запиши хотя бы один выход.")
            }
            TGExplainer(text: "Файл можно положить в «Файлы», отправить себе в мессенджер или сохранить в iCloud Drive. Внутри обычный JSON — его видно глазами.")
        }
    }

    private func sizeText(_ data: Data) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    // MARK: CSV

    /// Третья строка экрана с кадра `45-screens`: «CSV · 14 столбцов».
    ///
    /// **Второго экспорта здесь нет и не заводится.** Таблицу строит тот же
    /// `Exporter.csv`, который зовут `HealthScreen:678`, `VetSummaryScreen:182`
    /// и `DataPrivacyScreen:44`. Надстрочник экрана весь год обещал «iCloud ·
    /// JSON · CSV» — три слова, две дороги: CSV с этого экрана не уходил
    /// никуда.
    ///
    /// **Строки взяты из каталога, а не заведены.** «14 столбцов» и
    /// «14 столбцов · Numbers и Excel» лежат в `Localizable.xcstrings`
    /// переведёнными на четыре языка и до сегодня не имели в Swift ни одного
    /// читателя — то есть строку планировали, текст заказали и перевели,
    /// а экран не построили. Наш разобранный класс «поле без читателя».
    ///
    /// **Право спрашивается, потому что рядом оно спрашивается.**
    /// `DataPrivacyScreen` отдаёт тот же CSV только с правом `.exportData`
    /// (`:58`). Вторая дверь к той же выгрузке без этого вопроса сделала бы
    /// право необязательным, а запрет — видимостью. Отдельно и не мной:
    /// **JSON с этого экрана правом НЕ закрыт** (`exportCard`), и это
    /// расхождение старше моей правки — названо в отчёте, не починено молча.
    private var csvCard: some View {
        TGCard {
            // Заголовок — существующий ключ «выгрузить» (его же носит
            // карточка CSV в `DataPrivacyScreen`), а не новое слово:
            // каждый новый кириллический литерал — работа каталога,
            // а каталог сегодня не мой. Единственное новое слово на
            // экране — «CSV», и оно латиницей: `Tools/extract_texts.py`
            // собирает кириллицу, латинский литерал в каталог не едет
            // и без него показывается собой во всех пяти языках.
            TGSectionHeader(title: "выгрузить")
            ShareLink(
                item: CSVFile(name: "togo-dnevnik.csv",
                              text: Exporter.csv(events: Diary.active(events))),
                preview: SharePreview("Дневник Togo · CSV")
            ) {
                TGListRow(title: "CSV",
                          value: "14 столбцов",
                          systemImage: "tablecells",
                          accessory: .none)
            }
            .buttonStyle(.plain)
            // Пояснения под строкой нет, и это правка ПО КАДРУ.
            // Здесь стояло «14 столбцов · Numbers и Excel» — второй
            // живой читатель осиротевшей строки каталога. На кадре
            // `06-перенос-csv` вышло «14 столбцов» дважды подряд,
            // значением строки и подписью под ней. На эталоне
            // `45-screens` подписи нет вовсе.
            //
            // > Обе строки были верны по отдельности. Дефект в том,
            // > что их поставили рядом, и виден он только кадром.
        }
        .disabled(!appState.can(.exportData))
    }

    // MARK: Загрузка

    private var importCard: some View {
        TGCard {
            TGSectionHeader(title: "восстановить из файла")
            TGButton(title: "Выбрать файл", variant: .secondary, size: .medium,
                     systemImage: "square.and.arrow.down") {
                isImporting = true
            }
            TGExplainer(text: "Приложение спросит, заменить всё или добавить недостающее. Тот же файл, загруженный дважды, ничего не задваивает — записи сверяются между собой.")
        }
    }

    private func messageCard(_ message: Message) -> some View {
        TGBanner(tone: message.tone, title: .готовая(message.title), subtitle: .готовая(message.detail),
                 systemImage: message.tone == .alarm ? "exclamationmark.triangle" : "checkmark.seal")
    }

    private var formatCard: some View {
        TGCard {
            TGSectionHeader(title: "что внутри файла")
            ForEach(contents, id: \.self) { line in
                HStack(alignment: .top, spacing: Token.Space.s8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Token.Ink.secondary)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(line).textStyle(AppFont.caption).wraps()
                    Spacer(minLength: 0)
                }
            }
            TGExplainer(text: "Формат версии \(BackupService.currentFormatVersion). Файл из более новой версии приложения старая не прочитает и скажет об этом.")
        }
    }

    private let contents = [
        "Собака: кличка, вес, порода, порция, режим кормления, чем маркируешь",
        "Все записи ленты со временем и автором, включая удалённые — со следом",
        "Уход и напоминания, схемы лечения и отметки приёмов",
        "Занятия, шаги обучения и накопленный прогресс",
        "Семья: имена, роли и выданные права",
        "Поездки и эпизоды",
    ]

    // MARK: Действия

    private func rebuild() {
        guard !dogs.isEmpty else { archive = nil; fileData = nil; return }
        do {
            let built = try BackupService.archive(context: context, appVersion: settings.appVersion)
            archive = built
            fileData = try BackupService.encode(built)
        } catch {
            message = Message(tone: .alarm, title: String(localized: "Не удалось собрать файл"),
                              detail: error.localizedDescription)
        }
    }

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingArchive = try BackupService.decode(try Data(contentsOf: url))
            } catch {
                message = Message(tone: .alarm, title: String(localized: "Файл не подошёл"),
                                  detail: error.localizedDescription)
                UsageLog.note(.backup, "open", outcome: .failed)
            }
        case .failure(let error):
            message = Message(tone: .alarm, title: String(localized: "Не удалось открыть файл"),
                              detail: error.localizedDescription)
            UsageLog.note(.backup, "open", outcome: .failed)
        }
    }

    private func restore(using strategy: BackupService.Strategy) {
        guard let pendingArchive else { return }
        do {
            let count = try BackupService.restore(pendingArchive, into: context, strategy: strategy)
            message = Message(
                tone: .done,
                title: String(localized: "Восстановлено"),
                detail: strategy == .replace
                    ? String(localized: "Дневник заменён содержимым файла: \(pendingArchive.summary).")
                    : String(localized: "Добавлено новых записей: \(count). То, что уже было, осталось на месте.")
            )
            Haptics.success()
            UsageLog.note(.backup, strategy == .replace ? "replace" : "merge")
        } catch {
            message = Message(tone: .alarm, title: String(localized: "Не получилось восстановить"),
                              detail: error.localizedDescription)
            UsageLog.note(.backup, "restore", outcome: .failed)
        }
        self.pendingArchive = nil
        rebuild()
    }
}
