import SwiftUI
import StoreKit

/// Экран подписки. Всё, что требует App Store Review 3.1.2, стоит на своих
/// местах: что входит, сколько стоит, на какой срок, автопродление,
/// восстановление покупок и ссылки на условия и политику.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var store

    @State private var selected: Product?

    /// Право на пробный период спрашивается у StoreKit, а не пишется в текст.
    /// У того, кто уже подписывался, пробной недели нет; в App Store Connect
    /// её ещё надо завести руками (в `.storekit` она есть, в `subscriptions.json`
    /// — нет). Пока StoreKit не подтвердил оффер и право на него, кнопка
    /// называет цену и ничего не обещает: обещание, которого нет в чеке, —
    /// отказ по 3.1.2 и 2.3.1.
    @State private var trialEligible: [String: Bool] = [:]

    var body: some View {
        TGScreen(title: "Togo Pro") {
            if store.isPro {
                TGBanner(tone: .done, title: "Подписка активна",
                         subtitle: "Спасибо. Управлять ей можно в настройках App Store.",
                         systemImage: "checkmark.seal")
            }

            featureList
            freeList

            TGStateful(
                isLoading: store.isLoading,
                isEmpty: store.products.isEmpty,
                loadingMessage: "Спрашиваю цены у App Store…",
                emptyImage: "wifi.exclamationmark",
                emptyTitle: "Цены не загрузились",
                emptyMessage: "Обычно это связь. Приложение работает и без подписки — всё, что важно для безопасности собаки, бесплатно навсегда.",
                emptyActionTitle: "Попробовать снова",
                emptyAction: { Task { await store.load() } }
            ) {
                planPicker
            }

            if let error = store.lastError {
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: .готовая(error),
                         systemImage: "exclamationmark.triangle")
            }

            legalText
        } bottom: {
            TGButton(title: .готовая(buyTitle), isEnabled: selected != nil && !store.isPro) {
                Task { await buy() }
            }
            HStack(spacing: Token.Space.s16) {
                // Шесть нажатий в одну секунду 22.09 — все с отказом.
                // Пока идёт запрос, кнопка занята и это видно.
                Button {
                    Task { await store.restore() }
                } label: {
                    if store.isRestoring {
                        HStack(spacing: Token.Space.s8) {
                            ProgressView()
                            Text("Спрашиваю магазин…")
                        }
                    } else {
                        Text("Восстановить покупки")
                    }
                }
                .disabled(store.isRestoring)
                Button("Закрыть") { dismiss() }
            }
            .textStyle(AppFont.caption)
            .frame(maxWidth: .infinity)
        }
        .usageScreen(.paywall)
        .task {
            await store.load()
            selected = store.products.last
            for product in store.products {
                trialEligible[product.id] = await product.subscription?.isEligibleForIntroOffer ?? false
            }
        }
    }

    private var buyTitle: String {
        guard let selected, let period = selected.subscription?.subscriptionPeriod else { return "Выбери план" }
        let price = "\(selected.displayPrice) \(Self.billing(period))"
        if let trial = trialLength(selected) {
            return "\(trial) бесплатно · дальше \(price)"
        }
        return "Подписаться · \(price)"
    }

    private var featureList: some View {
        TGCard {
            TGSectionHeader(title: "что открывает")
            ForEach(SubscriptionStore.proFeatures, id: \.1) { symbol, title, detail in
                TGIconRow(symbol: symbol, title: .готовая(title), detail: .готовая(detail))
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
                        .foregroundStyle(Token.Action.doneText)
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
                    // Выбор передан кольцом и заливкой; VoiceOver узнаёт о нём
                    // только из трейта — иначе человек не слышит, что покупает.
                    TGTile(isSelected: selected?.id == product.id, minHeight: 68) {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: selected?.id == product.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(Token.Status.doneText)
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
                .accessibilityAddTraits(selected?.id == product.id ? .isSelected : [])
            }
        }
    }

    private var legalText: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            Text("Подписка продлевается сама, пока её не отменить — не позже чем за 24 часа до конца периода. Оплата спишется с Apple ID при подтверждении покупки. Отменить можно в настройках App Store.")
                .textStyle(AppFont.micro.color(Token.Ink.secondary))
            HStack(spacing: Token.Space.s16) {
                NavigationLink("Условия использования") { TermsScreen() }
                NavigationLink("Политика конфиденциальности") { PrivacyPolicyScreen() }
            }
            .textStyle(AppFont.caption)
        }
    }

    private func subscriptionCaption(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        if let trial = trialLength(product) {
            return "\(Self.billing(period)) · сначала \(trial) бесплатно"
        }
        return Self.billing(period)
    }

    /// «неделя», «2 недели», «месяц» — длина пробного периода, если он есть
    /// у продукта и человек имеет на него право. Иначе `nil`, и текст молчит.
    private func trialLength(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial,
              trialEligible[product.id] == true else { return nil }
        return Self.length(offer.period)
    }

    /// «в месяц», «в год», «каждые 3 месяца» — как часто списывается цена.
    /// Раньше строка складывалась как «каждые 1 месяц».
    static func billing(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.day, 1): return "в день"
        case (.week, 1): return "в неделю"
        case (.month, 1): return "в месяц"
        case (.year, 1): return "в год"
        default: return "каждые \(length(period))"
        }
    }

    static func length(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.week, 1): return "неделя"
        case (.month, 1): return "месяц"
        case (.year, 1): return "год"
        case (.day, let n): return Fmt.days(n)
        case (.week, let n): return Fmt.plural(n, "неделя", "недели", "недель")
        case (.month, let n): return Fmt.plural(n, "месяц", "месяца", "месяцев")
        case (.year, let n): return Fmt.plural(n, "год", "года", "лет")
        default: return ""
        }
    }

    private func buy() async {
        guard let selected else { return }
        await store.purchase(selected)
        if store.isPro { dismiss() }
    }
}
