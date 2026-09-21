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

    var body: some View {
        if dogs.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: Token.Space.s8) {
                    ForEach(dogs) { dog in
                        Button { appState.select(dog) } label: {
                            DogChip(dog: dog, isActive: dog.id == active?.id)
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
        }
    }
}

private struct DogChip: View {
    let dog: Dog
    let isActive: Bool

    var body: some View {
        HStack(spacing: Token.Space.s6) {
            TGAvatar(initial: dog.initial, image: dog.photo,
                     size: Token.Size.avatarSm,
                     tint: isActive ? Token.Action.doneQuiet : Token.Surface.sunken)
            Text(dog.name)
                .textStyle(isActive ? AppFont.captionEmphasis : AppFont.caption)
                .foregroundStyle(isActive ? Token.Ink.primary : Token.Ink.secondary)
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
struct DogsScreen: View {
    @Query(sort: \Dog.name) private var dogs: [Dog]
    @Environment(AppState.self) private var appState

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "кого смотрим",
                                subtitle: dogs.count > 1
                                    ? "весь дневник, план дня и напоминания — про выбранную"
                                    : nil)
                ForEach(dogs) { dog in
                    Button { appState.select(dog) } label: {
                        DogRow(dog: dog, isActive: dog.id == appState.activeDog(from: dogs)?.id)
                    }
                    .buttonStyle(.plain)
                    TGDivider()
                }
                if canEdit {
                    NavigationLink { DogEditorScreen() } label: {
                        TGListRow(title: "Завести ещё собаку", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            TGExplainer(text: "У каждой собаки свой дневник, своё питание и свой уход — они не смешиваются. Права в семье выдаются один раз и действуют на всех.")
        }
        .navigationTitle("Собаки")
        .navigationBarTitleDisplayMode(.large)
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
                Text(dog.name).textStyle(AppFont.body)
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
