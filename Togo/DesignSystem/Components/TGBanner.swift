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
    /// Насколько громко. Тихая — подложка тона и текст тона; сплошная —
    /// заливка цветом вида и тёмный (или белый) текст **на ней**.
    enum Emphasis: Sendable { case quiet, solid }

    let tone: TGTone
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String = "clock"
    var emphasis: Emphasis = .quiet

    /// Пара «сплошная заливка + чернила на ней» — **только у терракота**,
    /// и это граница по замеру, а не по вкусу.
    ///
    /// `Token.Category.onIncident` существует ровно для этого случая
    /// и несёт решение в себе: «#111 там, где заливка светлая, белый там,
    /// где тёмная». Поэтому пара режимная и выходит во всех четырёх
    /// (замер 24.10.2026, порог 4,5 · 7 в повышенном):
    ///
    /// ```
    /// dark     #111111 на #FF7A66   7,40:1   выходит
    /// light    #FFFFFF на #AE2219   6,90:1   выходит
    /// darkHC   #111111 на #FFA696  10,02:1   выходит
    /// lightHC  #FFFFFF на #9B100E   8,49:1   выходит
    /// ```
    ///
    /// **У `.done` и `.waiting` такой пары нет, и выдумывать её нельзя:**
    /// `Category.on*` заведён инциденту, а чернил «на мяте» и «на янтаре»
    /// в `tokens.json` не существует. Сплошная у них молча падает
    /// в тихую — нарисовать громкую мы можем, а назвать цвет подписи
    /// замером нет. Понадобится — это решение дизайна, не правка здесь.
    private var сплошная: (заливка: Color, чернила: Color)? {
        guard emphasis == .solid, tone == .alarm else { return nil }
        return (Token.Category.incident, Token.Category.onIncident)
    }

    private var чернила: Color { сплошная?.чернила ?? tone.foreground }
    private var подложка: Color { сплошная?.заливка ?? tone.background }

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Image(systemName: systemImage)
                .font(.system(size: Token.Size.iconLg - 2, weight: .semibold))
                .foregroundStyle(чернила)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                // Кегль поднят до section: мелкую плашку натощак можно было проскроллить.
                Text(title)
                    .font(.system(size: Token.Component.Banner.titleSize, weight: Token.FontWeight.semibold))
                    .foregroundStyle(чернила)
                    .wraps()
                if let subtitle {
                    Text(subtitle)
                        .textStyle(AppFont.caption.color(чернила))  // без .opacity(0.85): подпись «Кровь — это к врачу» падала до 3,6:1
                        .wraps()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Token.Component.Banner.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(подложка, in: RoundedRectangle(cornerRadius: Token.Component.Banner.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
