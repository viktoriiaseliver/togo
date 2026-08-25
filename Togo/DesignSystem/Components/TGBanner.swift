import SwiftUI

/// Figma: `Banner`. Свойство `tone` решает всё остальное.
///
/// Янтарь — «подожди», а не ошибка: это единственная роль окна натощак.
/// Терракот — просрочка или кровь. Зелёного «молодец» в палитре нет.
struct TGBanner: View {
    let tone: TGTone
    let title: String
    var subtitle: String?
    var systemImage: String = "clock"

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Image(systemName: systemImage)
                .font(.system(size: Token.Size.iconLg - 2, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                // Кегль поднят до section: мелкую плашку натощак можно было проскроллить.
                Text(title)
                    .font(.system(size: Token.Component.Banner.titleSize, weight: Token.FontWeight.semibold))
                    .foregroundStyle(tone.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption.color(tone.foreground.opacity(0.85)))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Token.Component.Banner.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background, in: RoundedRectangle(cornerRadius: Token.Component.Banner.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
