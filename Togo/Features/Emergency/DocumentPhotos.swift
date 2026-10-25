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

    /// Крупный системный кегль сужает сетку. Ответ дизайна 25.10.2026,
    /// круг 5, пункт 6: «3 колонки… при AX-размерах — 2 колонки».
    @Environment(\.dynamicTypeSize) private var размер

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
            }

            сетка
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

    // MARK: Сетка снимков

    /// Сетка 3 в ряд из плиток-фотографий плюс плитка «Снять».
    ///
    /// # Почему сетка, а не список
    ///
    /// Эталон v10, `36-screens.jpg`: шесть плиток по три в ряд, подпись
    /// лежит НА снимке слева внизу, последняя плитка — тёмная, со
    /// значком камеры и словом «Снять». У нас тут стоял вертикальный
    /// список строк с миниатюрой 44×44.
    ///
    /// Разница не в красоте. Снимок документа ищут **в спешке и глазами**
    /// — у врача, на границе, в гостинице, — и ищут по тому, КАК
    /// страница выглядит, а не по тому, как её назвали при съёмке.
    /// Миниатюра 44 pt этого не даёт: на ней не отличить страницу
    /// паспорта от страницы прививок. Шесть строк по 44 занимают
    /// столько же места, сколько шесть плиток, на которых видно.
    ///
    /// # Форма взята, а не придумана
    ///
    /// `LazyVGrid` в проекте живёт в четырёх местах; ближайшее
    /// по смыслу — `IncidentSheet:29`: `GridItem(.flexible())`,
    /// повторённый по числу колонок, с одинаковым зазором по обеим осям.
    /// Здесь то же самое, колонок три.
    ///
    /// # «Снять» — плитка сетки, а не строка под ней
    ///
    /// Так на кадре, и так же она ведёт себя правильно при нуле
    /// снимков: сетка из одной плитки «Снять» — это и есть пустое
    /// состояние, у которого вход виден. Отдельная строка под сеткой
    /// при нуле снимков оставляла бы пустую сетку и строку, то есть
    /// два пустых места вместо одного действия.
    @ViewBuilder
    private var сетка: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Token.Space.s8),
                                 count: Сетка.колонок(размер)),
                  spacing: Token.Space.s8) {
            ForEach(documents) { document in
                Button { viewing = document } label: {
                    ПлиткаСнимка(документ: document)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: document.title))
                .accessibilityAddTraits(.isButton)
            }

            if canEdit {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    ПлиткаСнять()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сфотографировать документ")
            }
        }
        .padding(.top, Token.Space.s8)
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
        guard context.persist(otherwise: { context.delete(document) }) else {
            return неСохранилось("Снимок не сохранился · попробуй ещё раз")
        }
        pendingImage = nil
        Haptics.success()
    }

    private func delete(_ document: DogDocument) {
        context.delete(document)
        guard context.persist(otherwise: {}) else {
            return неСохранилось("Снимок не удалился · попробуй ещё раз")
        }
        viewing = nil
        Haptics.warning()
    }

    /// Отказ виден человеку: снимок документа — то, что ищут в спешке,
    /// и «кажется, сохранил» здесь дороже обычного.
    private func неСохранилось(_ текст: String) {
        Haptics.warning()
        appState.showFailure(текст)
    }
}

/// Обёртка, чтобы снимок можно было отдать в `.sheet(item:)`.
private struct PendingPhoto: Identifiable {
    let data: Data
    var id: Int { data.hashValue }
}

/// Плитка сетки: сам снимок, подпись лежит НА нём слева внизу.
///
/// **Подпись не под плиткой, а на ней — и это не вкус.** Под плиткой
/// она задавала бы высоту ряда по самому длинному названию
/// («Ветпаспорт» против «Чип»), и три плитки в ряду разъезжались бы
/// по высоте от слов. На снимке подпись стоит на своей подложке
/// и высоту ряда не трогает вовсе.
///
/// Подложка под подписью обязательна по той же причине, что слой
/// затемнения у `CinemaHeader`: белый текст на СНИМКЕ — это текст
/// на неизвестном фоне, и светлая страница паспорта съедает его
/// целиком. Здесь фон под подписью свой и непрозрачный, поэтому пара
/// считается без снимка.
///
/// `Text(verbatim:)` у названия — потому что название **вводит
/// человек** (чипами в `DocumentTitleSheet` либо своим словом):
/// Числа сетки — одно место на обе плитки.
///
/// Ответ дизайна 25.10.2026, круг 5, пункт 6: «3 колонки, зазор 8,
/// ячейка 3 : 4, радиус 16; при AX-размерах — 2 колонки».
///
/// **Пропорция была 4 : 5 и стала 3 : 4, и разница не косметическая:**
/// при трёх колонках на 402 pt клетка 118 pt шириной даёт высоту 147
/// против 157 — ряд становится ниже на десять точек, и четвёртый ряд
/// на экран помещается там, где раньше помещалось три с половиной.
/// Число 3 : 4 — пропорция бумажного листа ближе, чем 4 : 5, а в сетке
/// лежат именно листы: паспорт, справка, выписка.
///
/// **Две колонки при AX — не «красивее», а единственный способ
/// оставить подпись читаемой:** у штампа есть пол высоты 28 и поля
/// 4 × 8, и на трети ширины при AX5 в него не влезает ни одно слово
/// целиком. Порог взят у системы (`DynamicTypeSize.isAccessibilitySize`),
/// а не числом точек: число точек пришлось бы держать в согласии
/// с системной шкалой руками.
private enum Сетка {
    /// `aspectRatio` принимает ОТНОШЕНИЕ ШИРИНЫ К ВЫСОТЕ, и 3 : 4
    /// здесь значит «уже, чем выше», то есть 0,75. Записано дробью,
    /// а не числом 0.75, чтобы в коде читалось то же, что в ответе
    /// дизайна: прочитанное как 4 : 3 перевернуло бы клетку набок.
    static let пропорция = 3.0 / 4.0

    static func колонок(_ размер: DynamicTypeSize) -> Int {
        размер.isAccessibilitySize ? 2 : 3
    }
}

/// это значение, а не ключ каталога, и `Text(ключ)` искал бы перевод
/// для «Ветпаспорт Стича».
private struct ПлиткаСнимка: View {
    let документ: DogDocument

    var body: some View {
        // **Пропорцию держит `Color.clear`, а не содержимое.**
        // `.aspectRatio(_:contentMode: .fit)`, надетый на стопку
        // с текстом, вписывает в пропорцию СОДЕРЖИМОЕ и размера клетке
        // не задаёт — ряд разъезжается от длины подписи. Гибкая пустая
        // подложка принимает предложенную ширину и из неё считает
        // высоту, а снимок и подпись ложатся на неё слоями.
        Color.clear
            .aspectRatio(Сетка.пропорция, contentMode: .fit)
            .overlay { снимок }
            .overlay(alignment: .bottomLeading) { подпись }
            .clipShape(RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var снимок: some View {
        if let data = документ.image, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            // Снимка нет — плитка остаётся плиткой, а не схлопывается
            // в полоску: пустое место в сетке читалось бы как «тут
            // ничего нет», а запись есть и её открывают.
            Token.Surface.sunken
                .overlay {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.medium))
                        .foregroundStyle(Token.Ink.secondary)
                }
                .accessibilityHidden(true)
        }
    }

    /// Числа — ответ дизайна 25.10.2026, круг 5, пункт 6, дословно:
    /// «подпись на снимке: стекло, отступ от краёв 8 (было 6), радиус 8
    /// (16 − 8), высота от 28, поля 4 × 8, 12 / 600».
    ///
    /// Четыре величины из пяти сделаны. **Кегль НЕ сделан, и это
    /// не забывчивость:** 12 ниже пола 14, поставленного решением
    /// Виктории 15.10.2026 («Пол 14, макет поправить»). Её
    /// формулировка называет и сторону починки — правится макет.
    /// Разбор с числами — в `$description` у `font.size.micro`
    /// в `DesignTokens/tokens.json`. Здесь остаётся `AppFont.micro`,
    /// то есть 14/400 против названных 12/600.
    ///
    /// «Было 6» в ответе дизайна — наш код, а не их макет: они
    /// смотрели сюда. Значит и остальные четыре числа читать надо
    /// как правку по месту, а не как общий стиль.
    private var подпись: some View {
        Text(verbatim: документ.title)
            .textStyle(AppFont.micro, color: Token.Poster.labelOnColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Token.Space.s8)
            .padding(.vertical, Token.Space.s4)
            .frame(minHeight: Token.Size.stampMin)
            .стекло(радиус: Token.Radius.stamp)
            .padding(Token.Space.s8)
    }
}

/// Плитка «Снять» — такая же клетка сетки, как снимки, с камерой.
///
/// Стоит последней и в том же ряду: так на кадре `36-screens.jpg`,
/// и так вход в механизм виден там, где человек уже смотрит.
private struct ПлиткаСнять: View {
    var body: some View {
        // Пропорцию держит та же пустая подложка, что у плитки снимка,
        // и по той же причине: иначе клетка «Снять» встала бы по высоте
        // своего текста, а не по высоте ряда, и выпала бы из сетки.
        Color.clear
            .aspectRatio(Сетка.пропорция, contentMode: .fit)
            .overlay {
                VStack(spacing: Token.Space.s6) {
                    Image(systemName: "camera")
                        .font(.system(size: Token.Size.iconXL, weight: Token.FontWeight.medium))
                        .accessibilityHidden(true)
                    // Дизайн просит 13/600, стоит 14/400: тринадцать
                    // ниже пола 14. См. `подпись` у плитки снимка.
                    Text("Снять")
                        .textStyle(AppFont.micro, color: Token.Ink.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Token.Ink.primary)
                .padding(.horizontal, Token.Space.s4)
            }
            .стекло(радиус: Token.Radius.tile)
            .contentShape(RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
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
        TGSheet(title: .готовая(document.title), subtitle: .готовая(Fmt.shortDay(document.addedAt))) {
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
