import Figma

/// Figma `Chip` → `TGChip`.
struct Chip_connection: FigmaConnect {
    let component = TGChip.self
    let figmaNodeUrl = "<FIGMA_FILE>?node-id=NODE_ID"

    @FigmaString("label")
    var title: String = "Кровь"

    @FigmaString("sublabel")
    var subtitle: String = ""

    @FigmaBoolean("selected")
    var isSelected: Bool = false

    @FigmaEnum("tone", mapping: [
        "neutral": TGTone.neutral,
        "alarm": TGTone.alarm,
    ])
    var tone: TGTone = .neutral

    var body: some View {
        TGChip(
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            isSelected: isSelected,
            tone: tone
        ) {}
    }
}
