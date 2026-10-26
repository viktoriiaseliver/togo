#if DEBUG
import SwiftUI

/// Витрина компонентов — та же роль, что у страницы библиотеки в Figma.
///
/// Каждый компонент показан всеми вариантами сразу. Если вариант появился
/// в Figma, он должен появиться здесь; если исчез здесь — его надо убрать
/// и там. Экран доступен только в отладочной сборке.
struct ComponentGallery: View {
    var body: some View {
        TGScreen(title: "Библиотека") {
            TGExplainer(text: "Имена компонентов совпадают с именами в Figma. Значения приходят из DesignTokens/tokens.json — руками в Swift их не правят.")

            group("Button") {
                ForEach(TGButton.Variant.allCases, id: \.self) { variant in
                    TGButton(title: "\(variant.rawValue)", variant: variant,
                             size: variant == .primary ? .large : .medium,
                             systemImage: "pawprint") {}
                }
                TGButton(title: "disabled", isEnabled: false) {}
            }

            group("Chip") {
                TGChipGroup(
                    items: ["rest", "selected", "alarm"],
                    title: { $0 },
                    isSelected: { $0 != "rest" },
                    tone: { $0 == "alarm" ? .alarm : .neutral }
                ) { _ in }
            }

            group("Banner") {
                ForEach(TGTone.allCases, id: \.self) { tone in
                    TGBanner(tone: tone, title: "tone · \(tone.rawValue)",
                             subtitle: "янтарь — «подожди», терракот — просрочка или кровь",
                             systemImage: "clock.badge.exclamationmark")
                }
            }

            group("ListRow") {
                TGCard(spacing: 0) {
                    TGListRow(title: "chevron", value: "значение", systemImage: "gearshape")
                    TGDivider()
                    TGListRow(title: "checkmark", accessory: .checkmark)
                    TGDivider()
                    TGListRow(title: "none", accessory: .none)
                }
            }

            group("Stat · Avatar · Author") {
                TGCard {
                    HStack(spacing: 0) {
                        TGStat(value: "60 г", caption: "съел")
                        TGStat(value: "190 мл", caption: "выпил")
                        TGStat(value: "2", caption: "выхода")
                        // Витрина нарочно оставлена строкой: она
                        // показывает сам `TGStat`, а ось раскладки
                        // показывать нечем — галерея снимается
                        // на обычном кегле.
                    }
                    TGDivider()
                    HStack(spacing: Token.Space.s12) {
                        TGAvatar(initial: "В")
                        TGAvatar(initial: "С", size: Token.Size.avatarMd, tint: Token.Action.primaryQuiet)
                        Spacer()
                        TGAuthorMark(author: "Тео")
                        TGAuthorMark(author: "Мама")
                    }
                }
            }

            group("Stepper") {
                TGCard { StepperPreview() }
            }

            group("Surface") {
                TGCard {
                    Text("Card на screen").textStyle(AppFont.body)
                    TGTile { Text("Tile внутри Card").textStyle(AppFont.caption).padding(Token.Space.s8) }
                    TGTile(isSelected: true) {
                        Text("Tile · selected").textStyle(AppFont.caption).padding(Token.Space.s8)
                    }
                }
            }

            group("Типографика") {
                TGCard {
                    Text("screenTitle").textStyle(AppFont.screenTitle)
                    Text("sectionTitle").textStyle(AppFont.sectionTitle)
                    Text("cardTitle").textStyle(AppFont.cardTitle)
                    Text("body").textStyle(AppFont.body)
                    Text("caption").textStyle(AppFont.caption)
                    Text("micro").textStyle(AppFont.micro)
                    Text("0123456789").textStyle(AppFont.numeric(22))
                }
            }

            group("Палитра") {
                TGCard {
                    swatchRow("Surface", [("screen", Token.Surface.screen), ("card", Token.Surface.card),
                                          ("sunken", Token.Surface.sunken), ("hairline", Token.Surface.hairline)])
                    swatchRow("Ink", [("primary", Token.Ink.primary), ("secondary", Token.Ink.secondary),
                                      ("faint", Token.Ink.faint), ("silhouette", Token.Ink.silhouette)])
                    swatchRow("Action", [("primary", Token.Action.primary), ("primaryQuiet", Token.Action.primaryQuiet),
                                         ("done", Token.Action.done), ("doneQuiet", Token.Action.doneQuiet)])
                    swatchRow("Status", [("waiting", Token.Status.waitingBg), ("waitingText", Token.Status.waitingText),
                                         ("overdue", Token.Status.overdueBg), ("overdueText", Token.Status.overdueText)])
                }
            }
        }
        .navigationTitle("Библиотека")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: .готовая(title))
            content()
        }
        .padding(.top, Token.Space.s8)
    }

    private func swatchRow(_ title: String, _ colors: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(title).textStyle(AppFont.micro)
            HStack(spacing: Token.Space.s6) {
                ForEach(colors, id: \.0) { name, color in
                    VStack(spacing: Token.Space.s4) {
                        RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                            .fill(color)
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous)
                                    .stroke(Token.Surface.hairline)
                            )
                        // Подпись названия токена — `secondary`, а не `faint`.
                        // Замер 05.10: `faint` на карточке даёт 3,43:1, и это
                        // единственное живое применение запрещённого токена
                        // во всём коде — то есть запрет нарушал не продукт,
                        // а сам инструмент, которым мы читаем имена цветов.
                        // Образец `faint` в списке выше остаётся: там он
                        // показывает себя заливкой, а не красит текст.
                        Text(name).font(.system(size: 9)).foregroundStyle(Token.Ink.secondary)
                    }
                }
            }
        }
    }
}

private struct StepperPreview: View {
    @State private var value = 60

    var body: some View {
        TGStepper(value: $value, unit: "граммов", step: 5, range: 0...600)
    }
}

#Preview {
    NavigationStack { ComponentGallery() }
}
#endif
