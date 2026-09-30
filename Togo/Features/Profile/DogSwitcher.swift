import SwiftUI
import SwiftData

/// Переключатель между собаками.
///
/// Модель с самого начала держала несколько собак — связи, бэкап, права
/// и вся арифметика написаны на многих, — но экраны брали первую попавшуюся.
/// То есть вторую собаку можно было завести и негде было открыть.
///
/// Показывается, только когда собак больше одной: у большинства она одна,
/// и лишний ряд в шапке ей ни к чему.
struct DogSwitcher: View {
    let dogs: [Dog]
    let active: Dog?

    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    var body: some View {
        if dogs.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: Token.Space.s8) {
                    ForEach(dogs) { dog in
                        // Закрытая без подписки собака видна — с замком —
                        // и ведёт на пейволл, а не исчезает: её записи
                        // целы, и человек должен видеть, где они.
                        let закрыта = appState.закрыта(dog, среди: dogs)
                        Button {
                            if закрыта { showPaywall = true } else { appState.select(dog) }
                        } label: {
                            DogChip(dog: dog, isActive: dog.id == active?.id, isLocked: закрыта)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Token.Spacing.screenPadding)
            }
            .scrollIndicators(.hidden)
            // Ряд вылезает за поля экрана, чтобы прокрутка доходила
            // до самого края: обрезанная на полпути карточка читается
            // как «дальше ничего нет».
            .padding(.horizontal, -Token.Spacing.screenPadding)
            .accessibilityLabel("Кого смотрим")
            .sheet(isPresented: $showPaywall) { NavigationStack { PaywallScreen() } }
        }
    }
}

private struct DogChip: View {
    let dog: Dog
    let isActive: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: Token.Space.s6) {
            TGAvatar(initial: dog.initial, image: dog.photo,
                     size: Token.Size.avatarSm,
                     tint: isActive ? Token.Action.doneQuiet : Token.Surface.sunken)
            Text(dog.name)
                .textStyle(isActive ? AppFont.captionEmphasis : AppFont.caption)
                .foregroundStyle(isActive ? Token.Ink.primary : Token.Ink.secondary)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .foregroundStyle(Token.Ink.secondary)
                    .accessibilityLabel("в Pro")
            }
        }
        .padding(.leading, Token.Space.s4)
        .padding(.trailing, Token.Space.s12)
        .frame(minHeight: Token.Size.tapTarget)
        .background(
            Capsule().fill(isActive ? Token.Action.doneQuiet : Token.Surface.card)
        )
        .overlay(
            Capsule().stroke(isActive ? Token.Action.doneText : Token.Surface.hairline,
                             lineWidth: isActive ? 1.5 : 1)
        )
        .contentShape(Capsule())
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// Список собак: переключиться, завести ещё одну.
///
/// Живёт в настройках собаки, а не в общих: это про собак, а не про
/// приложение. Заводится вторая ровно тем же экраном, что и первая.
///
/// Вторая и следующие собаки — Pro. До 30.09 отсюда в редактор вела
/// ссылка без проверки, и вторую собаку заводили без подписки: гейт
/// стоял только в настройках. Теперь оба пути спрашивают одно и то же —
/// `SubscriptionStore.canAddDog`.
struct DogsScreen: View {
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionStore.self) private var store
    @State private var showPaywall = false

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "кого смотрим",
                                subtitle: dogs.count > 1
                                    ? "весь дневник, план дня и напоминания — про выбранную"
                                    : nil)
                ForEach(dogs) { dog in
                    let закрыта = appState.закрыта(dog, среди: dogs)
                    Button {
                        if закрыта { showPaywall = true } else { appState.select(dog) }
                    } label: {
                        DogRow(dog: dog,
                               isActive: dog.id == appState.activeDog(from: dogs)?.id,
                               isLocked: закрыта)
                    }
                    .buttonStyle(.plain)
                    TGDivider()
                }
                if canEdit {
                    if store.canAddDog(existing: dogs.count) {
                        NavigationLink { DogEditorScreen() } label: {
                            TGListRow(title: "Завести ещё собаку", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { showPaywall = true } label: {
                            TGListRow(title: "Завести ещё собаку", value: "Pro", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if dogs.contains(where: { appState.закрыта($0, среди: dogs) }) {
                TGExplainer(text: "Без подписки открыта первая заведённая собака. Записи остальных никуда не делись — вернутся, как только снова включишь Pro.")
            }
            TGExplainer(text: "У каждой собаки свой дневник, своё питание и свой уход — они не смешиваются. Права в семье выдаются один раз и действуют на всех.")
        }
        .navigationTitle("Собаки")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallScreen() } }
    }
}

private struct DogRow: View {
    let dog: Dog
    let isActive: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            TGAvatar(initial: dog.initial, image: dog.photo,
                     size: Token.Size.avatarSm, tint: Token.Action.doneQuiet)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(dog.name).textStyle(AppFont.body)
                Text([dog.breed, dog.ageDescription].compactMap { $0 }.joined(separator: " · "))
                    .textStyle(AppFont.micro)
            }
            Spacer(minLength: 0)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .foregroundStyle(Token.Ink.secondary)
                    .accessibilityLabel("в Pro")
            } else if isActive {
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
