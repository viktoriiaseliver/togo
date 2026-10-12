import Figma

/// Figma `Button` → `TGButton`.
///
/// Свойства варианта в Figma названы так же, как параметры в Swift:
/// variant / size / systemImage / disabled.
struct Button_connection: FigmaConnect {
    let component = TGButton.self
    let figmaNodeUrl = "<FIGMA_FILE>?node-id=NODE_ID"

    @FigmaString("label")
    var title: String = "Вывожу"

    @FigmaEnum("variant", mapping: [
        "primary": TGButton.Variant.primary,
        "secondary": TGButton.Variant.secondary,
        "quiet": TGButton.Variant.quiet,
        "destructive": TGButton.Variant.destructive,
    ])
    var variant: TGButton.Variant = .primary

    @FigmaEnum("size", mapping: [
        "large": TGButton.Size.large,
        "medium": TGButton.Size.medium,
    ])
    var size: TGButton.Size = .large

    @FigmaString("systemImage")
    var systemImage: String = "figure.walk.departure"

    @FigmaBoolean("disabled")
    var disabled: Bool = false

    var body: some View {
        TGButton(
            title: title,
            variant: variant,
            size: size,
            systemImage: systemImage,
            isEnabled: !disabled
        ) {}
    }
}
