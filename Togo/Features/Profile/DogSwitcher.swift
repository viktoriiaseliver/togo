import SwiftUI
import SwiftData

/// Переключатель между собаками.
///
/// Модель с самого начала держала несколько собак — связи, бэкап, права
/// и вся арифметика написаны на многих, — но экраны брали первую попавшуюся.
/// То есть вторую собаку можно было завести и негде было открыть.
///
/// **С 23.10.2026 ряд показывается ВСЕГДА, а не только при двух собаках,
/// и причина — кадр.** `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/09.png`
/// рисует под описью две пилюли: выбранная собака белым и «+ Вторая
/// собака» тёмным. То есть ряд на кадре есть у человека с одной собакой,
/// и несёт он не переключение, а **вход**.
///
/// Прежнее условие `dogs.count > 1` было верным для своего довода
/// («лишний ряд ей ни к чему») и ложным для кадра: с ним пилюля
/// «+ Вторая собака» не показывалась бы никогда — ровно тому, кому
/// она адресована.
///
/// Дверь не вторая: «+ Вторая собака» ведёт в тот же `DogsScreen`, что
/// и строка списка «Завести ещё собаку». Два пути к одному экрану,
/// собранные порознь, расходятся молча — здесь они собраны одним
/// назначением.
struct DogSwitcher: View {
    let dogs: [Dog]
    let active: Dog?

    @Environment(AppState.self) private var appState

    var body: some View {
        if !dogs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: Token.Space.s8) {
                    ForEach(dogs) { dog in
                        Button { appState.select(dog) } label: {
                            DogChip(dog: dog, isActive: dog.id == active?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink { DogsScreen() } label: { ЕщёСобакаChip() }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, Token.Spacing.screenPadding)
            }
            .scrollIndicators(.hidden)
            // Ряд вылезает за поля экрана, чтобы прокрутка доходила
            // до самого края: обрезанная на полпути карточка читается
            // как «дальше ничего нет».
            .padding(.horizontal, -Token.Spacing.screenPadding)
            .accessibilityLabel("Кого смотрим")
        }
    }
}

private struct DogChip: View {
    let dog: Dog
    let isActive: Bool

    var body: some View {
        HStack(spacing: Token.Space.s6) {
            // **Тинт аватара белым НЕ красится, хотя пилюля белая.**
            // `TGAvatar` рисует букву `Token.Ink.primary`'ом жёстко
            // (`TGRows.swift`, «в тёмном наборе все аватарные фоны
            // тёмные»), то есть белым. Белая буква на белом круге —
            // это 1:1, и первый же кадр показал на месте пилюли пустое
            // белое пятно. Кружок здесь — слот под фотографию, а не
            // признак выбора; выбор показывает заливка пилюли.
            TGAvatar(initial: dog.initial, image: dog.photo,
                     size: Token.Size.avatarSm,
                     tint: Token.Surface.raised)
            // Цвет подставляется ВМЕСТО стилевого, а не поверх него.
            //
            // `AppFont.captionEmphasis` несёт свой `color`
            // (`Token.Ink.primary`, то есть белый), и `textStyle` красит
            // сам `Text` — соседний `.foregroundStyle` его не перебивает.
            // Так уже было: главная кнопка приложения давала 1,68:1
            // при зелёном тесте, который проверял ровно это место.
            // Здесь та же форма дала белое по белому, и поймал её кадр.
            //
            // Белая заливка с тёмной подписью — решение Виктории
            // 22.10.2026, «главная кнопка белая #FFFFFF с текстом
            // #111111». Прежняя пара (зелёный тинт `doneQuiet`
            // + `doneText`) осталась от Graphite, и на кадре `09` её нет.
            Text(dog.displayName)
                .textStyle(isActive
                           ? AppFont.captionEmphasis.color(Token.Ink.onAccent)
                           : AppFont.caption.color(Token.Ink.secondary))
        }
        .padding(.leading, Token.Space.s4)
        .padding(.trailing, Token.Space.s12)
        .frame(minHeight: Token.Size.tapTarget)
        .background(
            Capsule().fill(isActive ? Token.Action.primary : Token.Surface.card)
        )
        .overlay(
            Capsule().stroke(isActive ? Token.Action.primary : Token.Surface.hairline,
                             lineWidth: Token.Size.hairline)
        )
        .contentShape(Capsule())
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// «+ Вторая собака» с кадра `09`.
///
/// Надпись не считает собак нарочно. «Третья собака» на кадре не бывает,
/// а подставлять порядковое числительное на пяти языках значило бы
/// завести склонение там, где у двери одно и то же дело: завести ещё
/// одну. Число живёт в строке списка («Собаки · 2»), и там оно к месту.
private struct ЕщёСобакаChip: View {
    var body: some View {
        HStack(spacing: Token.Space.s6) {
            Image(systemName: "plus")
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .foregroundStyle(Token.Ink.secondary)
                .frame(width: Token.Size.avatarSm, height: Token.Size.avatarSm)
                .accessibilityHidden(true)
            Text("Вторая собака")
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.primary)
        }
        .padding(.leading, Token.Space.s4)
        .padding(.trailing, Token.Space.s12)
        .frame(minHeight: Token.Size.tapTarget)
        .background(Capsule().fill(Token.Surface.card))
        .overlay(Capsule().stroke(Token.Surface.hairline, lineWidth: Token.Size.hairline))
        .contentShape(Capsule())
    }
}

/// Список собак: переключиться, завести ещё одну.
///
/// Живёт в настройках собаки, а не в общих: это про собак, а не про
/// приложение. Заводится вторая ровно тем же экраном, что и первая.
///
/// # Ворота Pro здесь не было, и это обходило пейволл целиком
///
/// Замер 29.10.2026, по вызовам, а не по именам:
///
/// ```
/// grep 'ProGate.isOpen(.secondDog'   1 вхождение на всё дерево
///                                    SettingsScreen.swift:373
/// grep 'DogEditorScreen()'           ДВА: SettingsScreen:374
///                                    и DogSwitcher:162 (этот экран)
/// ```
///
/// То есть дверей, заводящих собаку, было две, а ворота стояли
/// на одной. Вторая дверь при этом **ближе**: «Настройки → Добавить
/// собаку» лежат за вкладкой настроек, а сюда ведут три входа подряд
/// — пилюля «+ Вторая собака» в переключателе (`DogSwitcher:41`),
/// строка «Собаки» на вкладке собаки (`DogTab:509`) и сам этот список.
/// Человек без подписки заводил вторую собаку, ни разу не увидев
/// пейволла, — а в пейволле «Вторая и следующие собаки» стоит первой
/// строкой из двух.
///
/// > **Ворота на одной двери из двух — не ворота, а украшение.**
/// > Ни компилятор, ни тест вопроса «а все ли двери» не задают:
/// > у закрытой и у несуществующей двери в коде одинаково ноль
/// > признаков.
///
/// Поэтому ворота здесь — **тот же вызов, что в настройках**, а не
/// свой `store.isPro`: фильтр показа применяет сама фабрика
/// `ProRequest.secondDog(among:)`, и повторять его на месте нельзя
/// (`dogs.count` и `dogs.shownToPerson.count` — один тип и разный
/// смысл, промах между ними компилируется). Гостя фабрика снимает
/// умолчанием `SharedZoneOwner.isGuest`: за собаку из чужого дневника
/// денег не берут.
///
/// Сторож на обе двери — `ProGateTests.каждаяДверьСобакиЗаВоротами`.
struct DogsScreen: View {
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionStore.self) private var store

    @State private var showPaywall = false

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            CinemaHeader("Собаки", надпись: "переключение", отступы: false)
            TGCard(spacing: 0) {
                TGSectionHeader(title: "кого смотрим",
                                subtitle: dogs.shownToPerson.count > 1
                                    ? "весь дневник, план дня и напоминания — про выбранную"
                                    : nil)
                // Фильтр один на весь показ — `shownToPerson`.
                // Безымянная строка в переключателе хуже, чем в списке:
                // на неё нажимают, и после нажатия весь дневник
                // становится пустым.
                ForEach(dogs.shownToPerson) { dog in
                    Button { appState.select(dog) } label: {
                        DogRow(dog: dog, isActive: dog.id == appState.activeDog(from: dogs)?.id)
                    }
                    .buttonStyle(.plain)
                    TGDivider()
                }
                // Два права подряд, и порядок у них не случайный.
                // `canEdit` — про роль: помощнику собаку заводить
                // нельзя ни за какие деньги, и пейволл ему показывать
                // значит продавать то, что не откроется. Ворота Pro —
                // про подписку, и они внутри.
                if canEdit {
                    if ProGate.isOpen(.secondDog(among: dogs), isPro: store.isPro) {
                        NavigationLink { DogEditorScreen() } label: {
                            TGListRow(title: "Завести ещё собаку", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Подпись меняется вместе с дверью, как
                        // в настройках: «Завести ещё собаку» за
                        // пейволлом обещало бы бесплатное.
                        // Обе строки уже лежат в каталоге на пяти
                        // языках — новых сюда не заводится.
                        Button { showPaywall = true } label: {
                            TGListRow(title: "Добавить вторую собаку", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TGExplainer(text: "У каждой собаки свой дневник, своё питание и свой уход — они не смешиваются. Права в семье выдаются один раз и действуют на всех.")
        }
        .navigationTitle("Собаки")
        .cinemaScreen()
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallScreen() }
        }
    }
}

private struct DogRow: View {
    let dog: Dog
    let isActive: Bool

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            TGAvatar(initial: dog.initial, image: dog.photo,
                     size: Token.Size.avatarSm, tint: Token.Action.doneQuiet)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(dog.displayName).textStyle(AppFont.body)
                Text([dog.breed, dog.ageDescription].compactMap { $0 }.joined(separator: " · "))
                    .textStyle(AppFont.micro)
            }
            Spacer(minLength: 0)
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Token.Status.doneText)
                    .accessibilityLabel("открыта сейчас")
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
        .contentShape(Rectangle())
    }
}
