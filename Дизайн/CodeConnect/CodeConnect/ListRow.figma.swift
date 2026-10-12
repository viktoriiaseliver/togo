import Figma

/// Figma `ListRow` → `TGListRow`.
struct ListRow_connection: FigmaConnect {
    let component = TGListRow.self
    let figmaNodeUrl = "<FIGMA_FILE>?node-id=NODE_ID"

    @FigmaString("title")
    var title: String = "Данные и приватность"

    @FigmaString("value")
    var value: String = ""

    @FigmaString("systemImage")
    var systemImage: String = "lock"

    @FigmaEnum("accessory", mapping: [
        "chevron": TGListRow.Accessory.chevron,
        "checkmark": TGListRow.Accessory.checkmark,
        "none": TGListRow.Accessory.none,
    ])
    var accessory: TGListRow.Accessory = .chevron

    var body: some View {
        TGListRow(
            title: title,
            value: value.isEmpty ? nil : value,
            systemImage: systemImage.isEmpty ? nil : systemImage,
            accessory: accessory
        )
    }
}
