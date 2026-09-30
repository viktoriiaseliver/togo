import SwiftUI

/// Объявление о пропаже: картинка и текст к ней.
///
/// До 30.09 здесь был только текст, без фото, и в нём стоял телефон
/// **ветеринара** — нашедший звонил бы в клинику, а не хозяину. Телефона
/// хозяина в модели нет, и схему ради него не трогаем: он живёт
/// в `UserDefaults` этого телефона (`phoneKey`) и попадает только сюда.
struct LostPosterCard: View {
    let dog: Dog

    @AppStorage(LostPoster.phoneKey) private var ownerPhone = ""
    @Environment(\.displayScale) private var displayScale
    @State private var poster: UIImage?

    var body: some View {
        TGCard {
            TGSectionHeader(title: "объявление, если потерялась",
                            subtitle: "фото, приметы, чип и твой телефон — картинкой и текстом")
            LabeledField(label: String(localized: "Твой телефон"),
                         spokenLabel: String(localized: "Твой телефон для объявления")) {
                TextField("+…", text: $ownerPhone).keyboardType(.phonePad)
            }
            TGExplainer(text: ownerPhone.isEmpty
                        ? "Впиши свой номер: без него на объявление некому ответить. Он хранится только на этом телефоне."
                        : "Номер хранится только на этом телефоне и попадает только в объявление.")
            if dog.photo == nil {
                TGExplainer(text: "Фото собаки нет — объявление выйдет без него. Добавить можно в профиле.")
            }
            if let poster {
                let image = Image(uiImage: poster)
                ShareLink(item: image,
                          subject: Text("Потерялась собака"),
                          message: Text(LostPoster.text(dog: dog, phone: ownerPhone)),
                          preview: SharePreview(LostPoster.headline(dog), image: image)) {
                    TGListRow(title: "Собрать объявление",
                              systemImage: "square.and.arrow.up", accessory: .none)
                }
                .buttonStyle(.plain)
            } else {
                ShareLink(item: LostPoster.text(dog: dog, phone: ownerPhone)) {
                    TGListRow(title: "Собрать объявление",
                              systemImage: "square.and.arrow.up", accessory: .none)
                }
                .buttonStyle(.plain)
            }
        }
        // Картинка пересобирается, когда меняется то, что на ней написано.
        .task(id: posterKey) { poster = render() }
    }

    private var posterKey: String {
        [dog.name, dog.breed ?? "", dog.distinctiveMarks ?? "", dog.chipNumber ?? "",
         ownerPhone, String(dog.photo?.count ?? 0), Fmt.weight(dog.weightKg)]
            .joined(separator: "|")
    }

    private func render() -> UIImage? {
        let renderer = ImageRenderer(content: LostPoster(dog: dog, phone: ownerPhone))
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

/// Сама картинка. Собирается `ImageRenderer`-ом, на экране не показывается.
struct LostPoster: View {
    let dog: Dog
    let phone: String

    /// Ключ телефона хозяина в `UserDefaults`.
    static let phoneKey = "lost.ownerPhone"

    /// Ширина картинки в точках. При масштабе экрана 3 это 1080 пикселей —
    /// ширина, которую мессенджеры и сторис показывают без пережатия.
    /// Размер холста, а не элемента интерфейса, поэтому токена у него нет.
    static let width: CGFloat = 360

    private var inner: CGFloat { Self.width - 2 * Token.Space.s20 }

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s12) {
            Text("Потерялась собака").textStyle(AppFont.caps.color(Token.Status.overdueText))
            if let data = dog.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: inner, height: inner * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: Token.Radius.card, style: .continuous))
            }
            Text(dog.name).textStyle(AppFont.display)
            Text(LostPoster.описание(dog)).textStyle(AppFont.body)
            ForEach(LostPoster.приметы(dog), id: \.0) { title, value in
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(title).textStyle(AppFont.caption)
                    Text(value).textStyle(AppFont.bodyEmphasis).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !phone.isEmpty {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Видели её — позвоните").textStyle(AppFont.caption)
                    Text(phone).textStyle(AppFont.display.color(Token.Action.doneText))
                }
                .padding(.top, Token.Space.s8)
            }
        }
        .padding(Token.Space.s20)
        .frame(width: Self.width, alignment: .leading)
        .background(Token.Surface.screen)
    }

    // MARK: Текст — один источник для картинки и подписи к ней

    static func headline(_ dog: Dog) -> String {
        String(localized: "Потерялась собака: \(dog.name)")
    }

    /// «шипперке · 4,1 кг · 3 лет».
    static func описание(_ dog: Dog) -> String {
        [dog.breed ?? String(localized: "метис"), Fmt.weight(dog.weightKg), dog.ageDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    static func приметы(_ dog: Dog) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let marks = dog.distinctiveMarks, !marks.isEmpty {
            rows.append((String(localized: "Приметы"), marks))
        }
        if let chip = dog.chipNumber, !chip.isEmpty {
            rows.append((String(localized: "Чип"), chip))
        }
        return rows
    }

    /// Текст к картинке — для тех, кто пересылает дальше словами.
    /// Телефона врача здесь нет намеренно: нашедший звонит хозяину.
    static func text(dog: Dog, phone: String) -> String {
        var parts = [headline(dog), описание(dog)]
        parts += приметы(dog).map { "\($0.0): \($0.1)" }
        if !phone.isEmpty { parts.append(String(localized: "Телефон: \(phone)")) }
        return parts.joined(separator: "\n")
    }
}
