import SwiftUI

/// Что будет, если отключить Pro.
///
/// Показывается до отмены, а не после. Приложение не прячет последствия
/// и не делает вид, что отменять некуда: ссылка на системный экран здесь же.
struct DowngradeScreen: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        TGScreen {
            TGCard {
                Text("Ничего не пропадёт").textStyle(AppFont.cardTitle)
                Text("Записи, занятия, история и схемы лечения останутся на месте. Закроется только часть экранов — и откроется обратно, если снова включить подписку.")
                    .textStyle(AppFont.caption)
            }

            TGCard {
                TGSectionHeader(title: "перестанет работать")
                ForEach(SubscriptionStore.lostOnDowngrade, id: \.1) { symbol, title, detail in
                    TGIconRow(symbol: symbol, title: title, detail: detail,
                              tint: Token.Status.waitingText)
                }
            }

            TGCard {
                TGSectionHeader(title: "останется навсегда")
                ForEach(SubscriptionStore.freeForever, id: \.self) { line in
                    HStack(spacing: Token.Space.s8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: Token.Size.iconSm, weight: .bold))
                            .foregroundStyle(Token.Action.done)
                            .accessibilityHidden(true)
                        Text(line).textStyle(AppFont.body)
                        Spacer(minLength: 0)
                    }
                }
                TGExplainer(text: "Без этих вещей приложение молча вредит собаке, поэтому они не продаются и после отмены никуда не денутся.")
            }

            TGCard {
                Text("Как отменить").textStyle(AppFont.cardTitle)
                Text("Отмена живёт у Apple, а не у нас: App Store → ваш Apple ID → Подписки. Подписка доработает до конца оплаченного периода.")
                    .textStyle(AppFont.caption)
                TGButton(title: "Открыть подписки в App Store", variant: .secondary, size: .medium,
                         systemImage: "arrow.up.right.square") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
            }
        }
        .navigationTitle("Отключить Pro")
        .navigationBarTitleDisplayMode(.large)
    }
}
