import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Фотографии документов: паспорт, чип, прививки, анализы.
///
/// Модель `DogDocument` лежала в схеме с самого начала — с полем под снимок
/// и каскадным удалением, — но экрана у неё не было ни одного. При этом
/// на «Документах» уже было написано, что фотографии паспорта удобно
/// держать здесь же: текст обещал то, чего в приложении не существовало.
struct DocumentPhotosCard: View {
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    /// Запросом, а не через связь: только что вставленный документ
    /// в обратной связи появляется не сразу, и список остался бы пустым.
    @Query(sort: \DogDocument.addedAt, order: .reverse) private var allDocuments: [DogDocument]

    @State private var picked: PhotosPickerItem?
    @State private var pendingImage: Data?
    @State private var viewing: DogDocument?

    private var documents: [DogDocument] {
        allDocuments.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "снимки",
                            subtitle: "паспорт и прививки спрашивают первыми — у врача, на границе и в гостинице")

            if documents.isEmpty {
                TGExplainer(text: "Пока ничего не сфотографировано. Снимки лежат на телефоне и никуда не отправляются.")
            } else {
                ForEach(documents) { document in
                    Button { viewing = document } label: {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                    TGDivider()
                }
            }

            if canEdit {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    TGListRow(title: documents.isEmpty ? "Сфотографировать документ" : "Ещё документ",
                              systemImage: "camera")
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: picked) { _, item in load(item) }
        .sheet(item: Binding(get: { pendingImage.map(PendingPhoto.init) },
                            set: { if $0 == nil { pendingImage = nil } })) { pending in
            DocumentTitleSheet(image: pending.data) { title, note in
                add(image: pending.data, title: title, note: note)
            }
        }
        .sheet(item: $viewing) { document in
            DocumentViewerSheet(document: document) { delete(document) }
        }
    }

    // MARK: Действия

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            // Полноразмерный снимок с камеры — это десятки мегабайт.
            // В дневнике он не нужен: читать надо номер, а не разглядывать
            // текстуру бумаги.
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let shrunk = DocumentPhoto.shrink(raw)
            else { return }
            pendingImage = shrunk
            picked = nil
        }
    }

    private func add(image: Data, title: String, note: String?) {
        let document = DogDocument(title: title, image: image, note: note)
        document.dog = dog
        context.insert(document)
        // Сохраняем сразу: обратная связь применяется не мгновенно,
        // и список остался бы прежним.
        try? context.save()
        pendingImage = nil
        Haptics.success()
    }

    private func delete(_ document: DogDocument) {
        context.delete(document)
        try? context.save()
        viewing = nil
        Haptics.warning()
    }
}

/// Обёртка, чтобы снимок можно было отдать в `.sheet(item:)`.
private struct PendingPhoto: Identifiable {
    let data: Data
    var id: Int { data.hashValue }
}

private struct DocumentRow: View {
    let document: DogDocument

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            DocumentThumbnail(data: document.image)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(document.title).textStyle(AppFont.body)
                Text(Fmt.shortDay(document.addedAt)).textStyle(AppFont.micro)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Token.Ink.faint)
        }
        .frame(minHeight: Token.Size.tapTarget)
        .contentShape(Rectangle())
    }
}

private struct DocumentThumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(Token.Ink.faint)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .background(Token.Surface.sunken,
                    in: RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Что это за бумага. Спрашиваем чипами, а не полем ввода: печатать
/// «Ветеринарный паспорт» каждый раз никто не станет.
struct DocumentTitleSheet: View {
    let image: Data
    var onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = DocumentPhoto.commonTitles[0]
    @State private var note = ""

    var body: some View {
        TGSheet(title: "Что это", subtitle: "чтобы потом найти не листая",
                closeTitle: "Отмена", hasUnsavedChanges: true) {
            TGCard {
                if let preview = UIImage(data: image) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                        .accessibilityLabel("Снимок документа")
                }
            }
            TGCard {
                TGChipGroup(items: DocumentPhoto.commonTitles, title: { $0 },
                            isSelected: { $0 == title }, minimumWidth: 120) { title = $0 }
                TGDivider()
                LabeledField(label: "Заметка") {
                    TextField("срок действия, кто выдал", text: $note)
                }
            }
        } footer: {
            TGButton(title: "Сохранить") {
                onSave(title, note.isEmpty ? nil : note)
                dismiss()
            }
        }
    }
}

/// Просмотр во весь экран — ровно то, что нужно показать на стойке.
struct DocumentViewerSheet: View {
    let document: DogDocument
    var onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        TGSheet(title: document.title, subtitle: Fmt.shortDay(document.addedAt)) {
            if let data = document.image, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    .accessibilityLabel(document.title)
            }
            if let note = document.note, !note.isEmpty {
                TGCard { Text(note).textStyle(AppFont.body).wraps() }
            }
            TGExplainer(text: "Снимок лежит на телефоне. Он попадает в резервную копию вместе с дневником и больше никуда не уходит.")
        } footer: {
            TGButton(title: "Удалить снимок", variant: .destructive,
                     size: .medium, systemImage: "trash") {
                isConfirmingDelete = true
            }
        }
        .confirmationDialog("Удалить снимок?", isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { onDelete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Фотография удалится с телефона. В галерее она останется, если снимали через камеру.")
        }
    }
}

/// Работа со снимком документа.
nonisolated enum DocumentPhoto {
    static let commonTitles = ["Паспорт", "Прививки", "Чип", "Анализы", "Назначение", "Другое"]

    /// Длинная сторона, до которой ужимаем. 1600 точек хватает, чтобы
    /// прочитать номер и печать, и в двадцать раз меньше исходника.
    static let maxSide: CGFloat = 1600
    static let quality: CGFloat = 0.7

    static func shrink(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image.jpegData(compressionQuality: quality) ?? data }

        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
