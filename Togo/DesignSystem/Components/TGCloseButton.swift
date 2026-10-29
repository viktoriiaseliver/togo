import SwiftUI

/// Figma: `CloseButton`. Кружок с крестиком в углу шторки.
///
/// Кружок рисуется 30×30 — так он не спорит с заголовком. Но нажимают
/// не кружок, а область вокруг него: Apple требует не меньше 44 пунктов,
/// и промах по кнопке «закрыть» человек воспринимает как зависшее окно.
/// Раньше эта пара «маленький кружок — маленькая цель» была скопирована
/// в двух местах, и оба раза без запаса.
struct TGCloseButton: View {
    var title: LocalizedStringKey = "Закрыть"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Token.Size.iconSm, weight: .bold))
                .foregroundStyle(Token.Ink.secondary)
                .frame(width: 30, height: 30)
                .background(Token.Surface.sunken, in: Circle())
                .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}
