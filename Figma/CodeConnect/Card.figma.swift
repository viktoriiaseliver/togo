import Figma

/// Figma `Card` → `TGCard`.
///
/// Слот `content` в Figma — это `@ViewBuilder` в коде. Карточка кладёт детям
/// свою поверхность в окружение, поэтому вложенные компоненты не нужно
/// настраивать отдельно — они наследуют её так же, как фрейм в Figma.
struct Card_connection: FigmaConnect {
    let component = TGCard<AnyView>.self
    let figmaNodeUrl = "<FIGMA_FILE>?node-id=NODE_ID"

    @FigmaEnum("surface", mapping: [
        "card": Theme.Surface.card,
        "sunken": Theme.Surface.sunken,
        "accent": Theme.Surface.accent,
    ])
    var surface: Theme.Surface = .card

    @FigmaBoolean("elevated")
    var elevated: Bool = true

    var body: some View {
        TGCard(surface: surface, elevated: elevated) {
            AnyView(Text("содержимое").textStyle(AppFont.body))
        }
    }
}
