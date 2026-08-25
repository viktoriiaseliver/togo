import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Перенос и восстановление.
///
/// Дневник живёт на телефоне — значит, у человека должен быть способ забрать
/// его с собой: на новый телефон, после переустановки, просто «на всякий».
/// Файл обычный JSON: его видно глазами и он не привязан к нашему серверу,
/// которого нет.
struct BackupScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(Settings.self) private var settings
    @Query private var dogs: [Dog]

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
            iCloudCard
            exportCard
            importCard
            if let message { messageCard(message) }
            formatCard
        }
        .navigationTitle("Перенос")
        .navigationBarTitleDisplayMode(.large)
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
            Text(pendingArchive.map { "В файле: \($0.summary). Сделан \(Fmt.shortDay($0.createdAt))." } ?? "")
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
                        .foregroundStyle(cloud.isGood ? Token.Action.done : Token.Ink.faint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(cloud.title).textStyle(AppFont.bodyEmphasis)
                        Text(cloud.detail)
                            .textStyle(AppFont.caption)
                            .fixedSize(horizontal: false, vertical: true)
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
                            subtitle: archive.map(\.summary) ?? "считаю…")
            if isBuilding {
                TGLoading(message: "Собираю файл из дневника…", isCompact: true)
            } else if let fileData, archive != nil {
                ShareLink(
                    item: BackupFile(name: BackupService.fileName(), data: fileData),
                    preview: SharePreview("Дневник Того")
                ) {
                    TGListRow(title: "Сохранить дневник в файл",
                              value: sizeText(fileData),
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

    // MARK: Загрузка

    private var importCard: some View {
        TGCard {
            TGSectionHeader(title: "восстановить из файла")
            TGButton(title: "Выбрать файл", variant: .secondary, size: .medium,
                     systemImage: "square.and.arrow.down") {
                isImporting = true
            }
            TGExplainer(text: "Приложение спросит, заменить всё или добавить недостающее. Повторная загрузка того же файла ничего не задваивает: записи сверяются по идентификатору.")
        }
    }

    private func messageCard(_ message: Message) -> some View {
        TGBanner(tone: message.tone, title: message.title, subtitle: message.detail,
                 systemImage: message.tone == .alarm ? "exclamationmark.triangle" : "checkmark.seal")
    }

    private var formatCard: some View {
        TGCard {
            TGSectionHeader(title: "что внутри файла")
            ForEach(contents, id: \.self) { line in
                HStack(alignment: .top, spacing: Token.Space.s8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Token.Ink.faint)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(line).textStyle(AppFont.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            TGExplainer(text: "Формат версии \(BackupService.currentFormatVersion). Файл, сделанный более новой версией приложения, старая читать не станет и честно об этом скажет.")
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
            message = Message(tone: .alarm, title: "Не удалось собрать файл",
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
                message = Message(tone: .alarm, title: "Файл не подошёл",
                                  detail: error.localizedDescription)
            }
        case .failure(let error):
            message = Message(tone: .alarm, title: "Не удалось открыть файл",
                              detail: error.localizedDescription)
        }
    }

    private func restore(using strategy: BackupService.Strategy) {
        guard let pendingArchive else { return }
        do {
            let count = try BackupService.restore(pendingArchive, into: context, strategy: strategy)
            message = Message(
                tone: .done,
                title: "Восстановлено",
                detail: strategy == .replace
                    ? "Дневник заменён содержимым файла: \(pendingArchive.summary)."
                    : "Добавлено новых записей: \(count). То, что уже было, осталось на месте."
            )
            Haptics.success()
        } catch {
            message = Message(tone: .alarm, title: "Не получилось восстановить",
                              detail: error.localizedDescription)
        }
        self.pendingArchive = nil
        rebuild()
    }
}
