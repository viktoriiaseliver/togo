import SwiftUI
import StoreKit

/// Экран подписки. Всё, что требует App Store Review 3.1.2, стоит на своих
/// местах: что входит, сколько стоит, на какой срок, автопродление,
/// восстановление покупок и ссылки на условия и политику.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store

    @State private var selected: Product?

    var body: some View {
        TGScreen(title: "Того Pro") {
            if store.isPro {
                TGBanner(tone: .done, title: "Подписка активна",
                         subtitle: "Спасибо. Управлять ей можно в настройках App Store.",
                         systemImage: "checkmark.seal")
            }

            featureList
            freeList
            planPicker

            if let error = store.lastError {
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: error,
                         systemImage: "exclamationmark.triangle")
            }

            legalText
        } bottom: {
            TGButton(title: buyTitle, isEnabled: selected != nil && !store.isPro) {
                Task { await buy() }
            }
            HStack(spacing: Token.Space.s16) {
                Button("Восстановить покупки") { Task { await store.restore() } }
                Button("Закрыть") { dismiss() }
            }
            .textStyle(AppFont.caption)
            .frame(maxWidth: .infinity)
        }
        .task {
            await store.load()
            selected = store.products.last
        }
    }

    private var buyTitle: String {
        guard let selected else { return "Выбери план" }
        return "Попробовать неделю бесплатно · дальше \(selected.displayPrice)"
    }

    private var featureList: some View {
        TGCard {
            TGSectionHeader(title: "что открывает")
            ForEach(SubscriptionStore.proFeatures, id: \.1) { symbol, title, detail in
                HStack(alignment: .top, spacing: Token.Space.s12) {
                    Image(systemName: symbol)
                        .font(.system(size: Token.Size.iconMd, weight: .medium))
                        .foregroundStyle(Token.Action.primary)
                        .frame(width: Token.Space.s24)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(title).textStyle(AppFont.bodyEmphasis)
                        Text(detail).textStyle(AppFont.caption)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var freeList: some View {
        TGCard {
            TGSectionHeader(title: "бесплатно навсегда",
                            subtitle: "без этого приложение молча вредит собаке, поэтому это не продаётся")
            ForEach(SubscriptionStore.freeForever, id: \.self) { line in
                HStack(spacing: Token.Space.s8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: Token.Size.iconSm, weight: .bold))
                        .foregroundStyle(Token.Action.done)
                    Text(line).textStyle(AppFont.body)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var planPicker: some View {
        VStack(spacing: Token.Space.s8) {
            ForEach(store.products, id: \.id) { product in
                Button { selected = product } label: {
                    TGTile(isSelected: selected?.id == product.id, minHeight: 68) {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: selected?.id == product.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(Token.Action.primary)
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(product.displayName).textStyle(AppFont.bodyEmphasis)
                                Text(subscriptionCaption(product)).textStyle(AppFont.caption)
                            }
                            Spacer(minLength: 0)
                            Text(product.displayPrice).textStyle(AppFont.numeric(17))
                        }
                        .padding(.horizontal, Token.Space.s14)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var legalText: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            Text("Подписка продлевается автоматически, пока её не отменить не позже чем за 24 часа до конца периода. Оплата спишется с Apple ID при подтверждении покупки. Отменить можно в настройках App Store.")
                .textStyle(AppFont.micro.color(Token.Ink.faint))
            HStack(spacing: Token.Space.s16) {
                NavigationLink("Условия использования") { TermsScreen() }
                NavigationLink("Политика конфиденциальности") { PrivacyPolicyScreen() }
            }
            .textStyle(AppFont.caption)
        }
    }

    private func subscriptionCaption(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let unit: String
        switch period.unit {
        case .day: unit = Fmt.days(period.value)
        case .week: unit = Fmt.plural(period.value, "неделя", "недели", "недель")
        case .month: unit = Fmt.plural(period.value, "месяц", "месяца", "месяцев")
        case .year: unit = Fmt.plural(period.value, "год", "года", "лет")
        @unknown default: unit = ""
        }
        return "каждые \(unit) · неделя бесплатно"
    }

    private func buy() async {
        guard let selected else { return }
        await store.purchase(selected)
        if store.isPro { dismiss() }
    }
}
