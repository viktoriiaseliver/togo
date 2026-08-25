import Figma

/// Figma `Banner` → `TGBanner`.
///
/// В Figma tone — вариант компонента; в коде это то же перечисление `TGTone`,
/// что и у чипа с плиткой. Одно свойство на всю библиотеку, а не три разных.
struct Banner_connection: FigmaConnect {
    let component = TGBanner.self
    let figmaNodeUrl = "<FIGMA_FILE>?node-id=NODE_ID"

    @FigmaEnum("tone", mapping: [
        "neutral": TGTone.neutral,
        "done": TGTone.done,
        "waiting": TGTone.waiting,
        "alarm": TGTone.alarm,
    ])
    var tone: TGTone = .waiting

    @FigmaString("title")
    var title: String = "Не кормить 2 ч 40 мин"

    @FigmaString("subtitle")
    var subtitle: String = "после таблетки в 19:00 · видят все"

    @FigmaString("systemImage")
    var systemImage: String = "clock.badge.exclamationmark"

    var body: some View {
        TGBanner(tone: tone, title: title, subtitle: subtitle, systemImage: systemImage)
    }
}
