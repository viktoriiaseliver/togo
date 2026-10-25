import SwiftUI
import StoreKit

/// Экран подписки в теме «Кино» — эталон `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/17.png`.
///
/// Всё, что требует App Store Review 3.1.2, стоит на своих местах: что
/// входит, сколько стоит, на какой срок, автопродление, восстановление
/// покупок и ссылки на условия и политику.
///
/// # Чего в макете есть, а здесь нет — названо, а не пропущено молча
///
/// ```
/// пять аватаров семей + «Семьи Боба, Люси, Тобика и ещё 1 200 собак»
///   УБРАНО ИЗ v1 РЕШЕНИЕМ ВИКТОРИИ 23.10.2026, дизайн подтвердила
///   тем же днём (`Дизайн/редизайн-ios28/ОТВЕТЫ-круг-3.md`, п. 4).
///   Основание не вкусовое: выдуманные отзывы и число на экране
///   оплаты — это App Review 2.3.1/3.1, плюс наше записанное
///   «ничего не обещаем ложно».
///
///   **Это не долг и не недоделка — возвращать по вкусу нельзя.**
///   Два условия возврата записаны там, где их прочтёт рисующий,
///   а не здесь: `Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`, раздел «Убрано
///   из v1 по App Review». Коротко: число настоящее, из ASC
///   или аналитики, от порога и с сервера; отзывы настоящие,
///   с согласия автора. Макет комментарии Swift не читает,
///   и из этого же файла обещание уже возвращалось через макет.
///
/// значок строки в заливке (`--action-subtle` под `--action-on-subtle`)
///   НЕ СДЕЛАНО: строка набрана `TGIconRow`, у него значок без плашки,
///   а `Togo/DesignSystem/**` этой смене не открыт. Пятую копию строки
///   рядом с четырьмя разошедшимися заводить нельзя — об этом написано
///   в голове самого `TGIconRow`.
///
/// восстановление покупок · автопродление · условия и политика
///   В МАКЕТЕ ИХ НЕТ, и они ОСТАВЛЕНЫ. Это не вкус: без них отказ
///   по 3.1.2, и он уже был. Макет про ревью не знает.
/// ```
///
/// # Что Pro открывает
///
/// Три вещи, и список выводится из `ProFeature`, а не лежит здесь
/// копией. **Трогать подписи нельзя, не прочитав
/// `Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`, раздел «Что Pro открывает, и чего
/// в подписи обещать нельзя»**: оттуда трижды убирали обещание
/// без дороги в коде, и на третий раз оно вернулось через макет.
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
        TGScreen {
            шапка

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
                emptySubject: .offline,
                emptyTitle: "Цены не загрузились",
                // Причину называем ту, что случилась, а не самую частую.
                // «Обычно это связь» стояло здесь всегда — и было
                // догадкой: 23.09 магазин отвечал пустым списком без
                // единой ошибки связи, и человек читал про связь,
                // починить которую нечем.
                emptyMessage: .готовая(пустоПочему),
                emptyActionTitle: "Попробовать снова",
                emptyAction: { Task { await store.load() } }
            ) {
                planPicker
            }

            if let error = store.lastError {
                TGBanner(tone: .alarm, title: "Не получилось", subtitle: .готовая(error),
                         systemImage: "exclamationmark.triangle")
            }

            восстановление
            legalText
        }
        // **Низ отдан системе, а не слоту `TGScreen`, и это починка
        // по кадру, а не вкус.** Первый кадр приёмки 23.10.2026
        // (`Дизайн/кадры-приёмки/редизайн-онбординга-и-pro-23.10/`)
        // показал белую кнопку поверх абзаца про автопродление
        // и «Не сейчас» поверх «Политики конфиденциальности»:
        // у слота `TGScreen` подложки нет вовсе (решение дизайна,
        // записано в самом каркасе), поэтому содержимое просвечивает
        // сквозь панель на любом положении прокрутки.
        //
        // `safeAreaInset` отдаёт панели настоящую подложку и сам
        // добавляет отступ в прокрутку, то есть под панель не уходит
        // ничего и ни при какой прокрутке. Тот же приём уже стоит
        // в `DogStep` и в ветке повтора `OnboardingFlow` — третьим
        // местом, а не изобретением.
        //
        // Подложку выбирать нельзя произвольно: правовой текст
        // и «Восстановить покупки» требуются ревью, и если их закрыть
        // полупрозрачной панелью, отказ придёт не по вёрстке,
        // а по 3.1.2.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Token.Space.s8) {
                TGButton(title: .готовая(buyTitle), isEnabled: selected != nil && !store.isPro) {
                    Task { await buy() }
                }
                // «Не сейчас», а не «Закрыть»: в макете это ссылка под
                // кнопкой, и слово там другое. Отказ от покупки — не выход
                // с экрана, и называть его надо тем, что человек делает.
                Button("Не сейчас") { dismiss() }
                    .textStyle(AppFont.bodyEmphasis.color(Token.Ink.link))
                    .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.top, Token.Space.s10)
            .padding(.bottom, Token.Space.s8)
            .background(.regularMaterial)
        }
        // «Отмена» слева в шапке — ровно как на кадре 17. Второй выход
        // рядом с «Не сейчас» не лишний: шторку закрывают и свайпом,
        // и кнопкой, и человек ищет её там, где она стоит в системе.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Отмена") { dismiss() }
            }
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

    /// Шапка листа: название и чем он является одной строкой.
    ///
    /// # ЧИСЛО СЧИТАЕТ КОД, А НЕ ПИШЕТ ЧЕЛОВЕК (решение дизайна 25.10.2026)
    ///
    /// Стояло «ровно три вещи» литералом, а `ProFeature.allCases` дал
    /// **два** с 24.10 — в тот день Виктория убрала перенос навыка
    /// из Pro («убери обещание и матрицу, это просто помощь»).
    /// Подзаголовок обещал три и перечислял две, и прожил так день.
    ///
    /// **Связь была построена в одну сторону.** Доккомментарий здесь
    /// говорил «четвёртая не может появиться в подписи, не появившись
    /// в воротах» — и это верно: от ПОЯВЛЕНИЯ защита была. От
    /// ИСЧЕЗНОВЕНИЯ не было ничего, потому что литерал не знает,
    /// сколько случаев в перечислении.
    ///
    /// > **Односторонний сторож выглядит как двусторонний.** Он
    /// > проверяет то, что легко придумать (прибавили), и молчит
    /// > о том, что случается чаще (убрали).
    ///
    /// Ответ дизайна, круг 6, пункт 9, дословно: «Число не литерал:
    /// его считает код из `ProFeature.allCases.count` через склонение
    /// каталога. Тест падает и когда пункт появился, и когда пропал».
    ///
    /// Склонение держит каталог: ключ `ровно %lld вещи` несёт формы
    /// числа, и «две вещи» против «три вещи» против «одну вещь» —
    /// его работа, а не наша арифметика по падежам.
    private var шапка: some View {
        VStack(spacing: Token.Space.s2) {
            Text("Togo Pro")
                .textStyle(AppFont.cardTitle)
                .accessibilityAddTraits(.isHeader)
            // **Отдельным элементом, а не склейкой с заголовком.**
            // `.accessibilityElement(children: .combine)` здесь стояло
            // и было снято: склейка убирает обе подписи из дерева,
            // а на этот подзаголовок стоят якоря трёх UI-наборов
            // (`ScreenshotTests` · `ПейволлКино` · `КегльAX5`),
            // по которым они узнают, что пейволл открылся.
            Text(Self.сколькоВещей).textStyle(AppFont.caption)
        }
        .frame(maxWidth: .infinity)
    }

    /// «ровно две вещи» — число из перечисления, склонение из каталога.
    ///
    /// `static`, потому что это утверждение о продукте, а не о состоянии
    /// экрана: его спрашивают и тесты, и якоря UI-наборов, и спрашивать
    /// им нужно ровно то, что рисуется.
    static var сколькоВещей: String {
        String(localized: "ровно \(ProFeature.allCases.count) вещи")
    }

    /// Почему цен нет — по тому, что ответил магазин.
    private var пустоПочему: String {
        switch store.ответМагазина {
        case .пусто:
            // Причина найдена 23.09 и она не в приложении: пока
            // не подписано Соглашение о платных приложениях, App Store
            // не отдаёт покупки вовсе — при любом состоянии продуктов
            // и в любой сборке. Человеку про соглашение знать незачем,
            // но знать, что дело не в нём и не в связи, — обязательно.
            String(localized: "Магазин не отдаёт подписки. Это не связь и не твой телефон: покупки ещё не включены на стороне App Store. Всё, что важно для безопасности собаки, бесплатно навсегда.")
        case .частично(let получено, let просили):
            String(localized: "Магазин дал \(получено) из \(просили) подписок. Показывать половину плана нечестно — покажем, когда придут обе.")
        case .ошибка:
            String(localized: "Не дозвонились до магазина. Обычно это связь. Приложение работает и без подписки — всё, что важно для безопасности собаки, бесплатно навсегда.")
        case .неСпрашивали, .всё:
            String(localized: "Обычно это связь. Приложение работает и без подписки — всё, что важно для безопасности собаки, бесплатно навсегда.")
        }
    }

    /// Подпись главной кнопки.
    ///
    /// Макет пишет «Togo Pro · 2,99 € в месяц» — название плюс цена,
    /// а не глагол. Цена приходит из StoreKit (`displayPrice`), а не
    /// из макета: «2,99 €» в кадре — это French storefront прототипа,
    /// и вписать его числом значило бы показать чужую валюту тому,
    /// у кого другая.
    private var buyTitle: String {
        guard let selected, let period = selected.subscription?.subscriptionPeriod else { return String(localized: "Выбери план") }
        let price = "\(selected.displayPrice) \(Self.billing(period))"
        if let trial = trialLength(selected) {
            return String(localized: "\(trial) бесплатно · дальше \(price)")
        }
        return String(localized: "Togo Pro · \(price)")
    }

    /// Три строки одной карточкой с разделителями — как на кадре.
    ///
    /// По индексам, а не `id: \.1` по кортежу: **ключевого пути
    /// к элементу кортежа в Swift не существует**, и прежняя форма
    /// держалась на том, что `ForEach` выводил его сам. Разделитель
    /// между строками требует знать, какая по счёту, — а значит индекс
    /// нужен в любом случае.
    private var featureList: some View {
        let вещи = SubscriptionStore.proFeatures
        return TGCard(spacing: 0) {
            ForEach(вещи.indices, id: \.self) { индекс in
                if индекс > 0 { TGDivider() }
                TGIconRow(symbol: вещи[индекс].0,
                          title: .готовая(вещи[индекс].1),
                          detail: .готовая(вещи[индекс].2),
                          tint: Token.Ink.link)
                    .padding(.vertical, Token.Space.s12)
            }
        }
    }

    /// Бесплатное — одной строкой под списком, как на кадре.
    ///
    /// **Список берётся из `SubscriptionStore.freeForever`, а не
    /// печатается здесь.** На кадре названы три пункта из пяти
    /// («окно натощак, защита от двойной дозы, отчёт врачу»); взять
    /// три значило бы завести вторую копию списка, которая разойдётся
    /// с первой молча. Отчёт врачу в этом списке не упомянут потому,
    /// что он не «бесплатная часть подписки», а то, чего в подписке
    /// нет вовсе: ворот у экспорта не существует ни одних.
    ///
    /// > **Строки `freeForever` — обычные `String`, и в каталог они
    /// > не уезжают** (`Text(String)` рисует дословно). То есть француз
    /// > читает их по-русски, и было так и до редизайна. Правка —
    /// > не здесь, а в `Subscriptions.swift`, и она задевает ещё
    /// > `DowngradeScreen`; названо, а не починено попутно.
    private var freeList: some View {
        VStack(spacing: Token.Space.s4) {
            Text("бесплатно навсегда")
                .textStyle(AppFont.caps)
                .textCase(.uppercase)
            Text(verbatim: SubscriptionStore.freeForever.joined(separator: " · "))
                .textStyle(AppFont.caption)
                .multilineTextAlignment(.center)
                .wraps()
        }
        .frame(maxWidth: .infinity)
    }

    private var planPicker: some View {
        VStack(spacing: Token.Space.s8) {
            ForEach(store.products, id: \.id) { product in
                Button { selected = product } label: {
                    // Выбор передан кольцом и заливкой; VoiceOver узнаёт о нём
                    // только из трейта — иначе человек не слышит, что покупает.
                    TGTile(isSelected: selected?.id == product.id, minHeight: Token.Size.capsule) {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: selected?.id == product.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(Token.Ink.link)
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(product.displayName).textStyle(AppFont.bodyEmphasis)
                                Text(subscriptionCaption(product)).textStyle(AppFont.caption)
                            }
                            Spacer(minLength: 0)
                            Text(product.displayPrice).textStyle(AppFont.numeric(Token.FontSize.body))
                        }
                        .padding(.horizontal, Token.Space.s14)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected?.id == product.id ? .isSelected : [])
            }
        }
    }

    /// Восстановление покупок. В макете его нет — в ревью оно есть.
    private var восстановление: some View {
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
        .textStyle(AppFont.caption)
        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
    }

    private var legalText: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            Text("Подписка продлевается сама, пока её не отменить — не позже чем за 24 часа до конца периода. Оплата спишется с Apple ID при подтверждении покупки. Отменить можно в настройках App Store.")
                .textStyle(AppFont.micro.color(Token.Ink.secondary))
                .wraps()
            // **Столбиком, а не в строку, и это тоже кадр.** В строку
            // две ссылки влезают по-английски и не влезают по-русски:
            // «Политика конфиденциальности» переносится на вторую
            // строку и наезжает на соседку. У французского и казахского
            // подписи ещё на четверть длиннее — то есть строка не
            // «почти помещается», она не помещается нигде, кроме
            // языка разработки.
            VStack(alignment: .leading, spacing: Token.Space.s8) {
                NavigationLink("Условия использования") { TermsScreen() }
                NavigationLink("Политика конфиденциальности") { PrivacyPolicyScreen() }
            }
            .textStyle(AppFont.caption)
        }
    }

    private func subscriptionCaption(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        if let trial = trialLength(product) {
            return String(localized: "\(Self.billing(period)) · сначала \(trial) бесплатно")
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
        case (.day, 1): return String(localized: "в день")
        case (.week, 1): return String(localized: "в неделю")
        case (.month, 1): return String(localized: "в месяц")
        case (.year, 1): return String(localized: "в год")
        default: return String(localized: "каждые \(length(period))")
        }
    }

    static func length(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.week, 1): return String(localized: "неделя")
        case (.month, 1): return String(localized: "месяц")
        case (.year, 1): return String(localized: "год")
        case (.day, let n): return Fmt.days(n)
        case (.week, let n): return String(localized: "\(n) недель")
        case (.month, let n): return String(localized: "\(n) месяцев")
        case (.year, let n): return String(localized: "\(n) лет")
        default: return ""
        }
    }

    private func buy() async {
        guard let selected else { return }
        await store.purchase(selected)
        if store.isPro { dismiss() }
    }
}
