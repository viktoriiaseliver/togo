import SwiftUI

/// Figma: `Banner`. Свойство `tone` решает всё остальное.
///
/// Янтарь — «подожди», а не ошибка. Ролей у него **три**, и все живые:
/// окно натощак (`TGBanner` с тоном `.waiting`), «почти вовремя»
/// (`MarkAccuracy.almost`, `DomainStyle:31`) и «навык тренируется»
/// (`SkillStatus.learning`, `DomainStyle:21`). Все три приземляются
/// на одну пару `Status.waitingBg` + `Status.waitingText`.
///
/// Здесь стояло «это единственная роль окна натощак» — требование
/// хендоффа дизайна («янтарь только натощак»), **отменённое решением
/// Виктории 05.10.2026**: жёлтый остаётся всем трём смыслам. Комментарий
/// пережил отмену и читался как действующее ограничение, то есть запрещал
/// то, что код уже делает по решению. Правится документ под код, а не
/// наоборот — и документ этот стоит в коде, потому его и видно позже всех.
///
/// Терракот — просрочка или кровь. Зелёного «молодец» в палитре нет.
struct TGBanner: View {
    let tone: TGTone
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
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
                    .wraps()
                if let subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption.color(tone.foreground))  // без .opacity(0.85): подпись «Кровь — это к врачу» падала до 3,6:1
                        .wraps()
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
