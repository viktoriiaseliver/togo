import SwiftUI
import SwiftData

/// Вкладка «Собака».
///
/// Появилась после ревизии иерархии по HIG. Раньше всё про собаку —
/// питание, уход, документы, цикл, поездка, «если что-то случилось» —
/// висело под профилем, а профиль открывался из шторки «Ещё». То есть
/// запас корма лежал на четвёртом уровне вложенности, да ещё и внутри
/// модального экрана, из которого Apple прямо не советует строить
/// длинные цепочки.
///
/// Теперь это плоский список под своей вкладкой: до любого экрана
/// два тапа вместо четырёх.
struct DogTab: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var trips: [Trip]

    private var dog: Dog? { appState.activeDog(from: dogs) }

    var body: some View {
        NavigationStack {
            TGScreen {
                if let dog {
                    DogSwitcher(dogs: dogs, active: dog)
                    header(dog)
                    emergency(dog)
                    everyday(dog)
                    documents(dog)
                    travel(dog)
                } else {
                    EmptyStateCard(
                        systemImage: "pawprint",
                        title: "Собаки пока нет",
                        message: "Заведи её — и приложению будет что считать.",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
            .navigationTitle(dog?.name ?? "Собака")
            .usageScreen(.profile)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { SettingsToolbarItem() }
        }
    }

    // MARK: Шапка

    private func header(_ dog: Dog) -> some View {
        NavigationLink { ProfileScreen(dog: dog) } label: {
            TGCard {
                HStack(spacing: Token.Space.s12) {
                    TGAvatar(initial: dog.initial, image: dog.photo,
                             size: Token.Size.avatarMd, tint: Token.Action.doneQuiet)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(dog.name).textStyle(AppFont.cardTitle)
                        Text([dog.breed, dog.ageDescription, Fmt.weight(dog.weightKg)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .textStyle(AppFont.caption)
                            .wraps()
                    }
                    Spacer(minLength: Token.Space.s8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Token.Size.iconSm, weight: .semibold))
                        .foregroundStyle(Token.Ink.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Первым блоком и в терракоте: искать это в панике некогда.
    private func emergency(_ dog: Dog) -> some View {
        NavigationLink { EmergencyScreen(dog: dog) } label: {
            TGCard(padding: Token.Space.s14) {
                TGListRow(title: "Если что-то случилось",
                          value: "телефоны и что сказать врачу",
                          systemImage: "cross.case",
                          tone: Token.Status.overdueText)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Каждый день

    private func everyday(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "каждый день")
                        TGLink(title: "Питание и режим", value: "\(dog.dailyGrams) г в день", systemImage: "fork.knife") { FeedingScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Уход", value: careSummary(dog).map { .готовая($0) }, systemImage: "scissors") { CareScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Вес", value: .готовая(Fmt.weight(dog.weightKg)), systemImage: "scalemass") { WeightScreen(dog: dog) }
            TGDivider()
            TGLink(title: "Перенос навыка", systemImage: "square.grid.3x3") { TransferMatrixScreen(dog: dog) }
            TGDivider()
            TGLink(title: "Занятия и шаги", value: trainingSummary(dog).map { .готовая($0) },
                   systemImage: "list.bullet") { TrainingLibraryScreen(dog: dog) }
            TGDivider()
            TGLink(title: dogs.count > 1 ? "Собаки" : "Завести ещё собаку",
                   value: dogs.count > 1 ? "\(dogs.count)" : nil,
                   systemImage: "pawprint") { DogsScreen() }
        }
        .buttonStyle(.plain)
    }

    private func careSummary(_ dog: Dog) -> String? {
        let due = dog.careTasks.filter { $0.isDue() }.count
        return due > 0 ? "\(due) сегодня" : nil
    }

    private func trainingSummary(_ dog: Dog) -> String? {
        let count = dog.trainingSessions.count
        return count == 0 ? nil : Fmt.plural(count, "занятие", "занятия", "занятий")
    }

    // MARK: Документы и цикл

    private func documents(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "на случай, когда спросят")
                        TGLink(title: "Документы и контакты", value: dog.chipNumber == nil ? "не заполнены" : nil, systemImage: "doc.text.image") { DocumentsScreen(dog: dog) }
            if dog.tracksHeat {
                TGDivider()
                                TGLink(title: "Цикл", value: HeatCycle.forecast(dog.heats).expectedNext.map { .готовая(Fmt.shortDay($0)) }, systemImage: "calendar.badge.clock") { HeatScreen(dog: dog) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Поездки

    private func travel(_ dog: Dog) -> some View {
        let мои = trips.filter { $0.dog?.persistentModelID == dog.persistentModelID }
            .sorted { $0.startDate > $1.startDate }
        return TGCard(spacing: 0) {
            TGSectionHeader(title: "поездки",
                            subtitle: мои.isEmpty ? "режим включится сам в день отъезда" : nil)
            ForEach(мои) { trip in
                TGLink(title: .готовая(trip.destination),
                       value: trip.isActive() ? "идёт" : .готовая(Fmt.shortDay(trip.startDate)),
                       systemImage: trip.transport.symbol) { TripScreen(trip: trip, dog: dog) }
                TGDivider()
            }
                        TGLink(title: мои.isEmpty ? "Запланировать поездку" : "Ещё поездка", systemImage: "plus") { TripSetupScreen(dog: dog) }
        }
        .buttonStyle(.plain)
    }
}

/// Шестерёнка настроек. Одна и та же на всех вкладках: Apple ждёт, что
/// настройки лежат в предсказуемом месте, а не только на первом экране.
struct SettingsToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { SettingsScreen() } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Настройки")
            }
        }
    }
}

/// Заведённая поездка: что взять и когда что делать.
struct TripScreen: View {
    let trip: Trip
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        TGScreen {
            TGCard {
                HStack {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(trip.destination).textStyle(AppFont.cardTitle)
                        Text("\(Fmt.shortDay(trip.startDate)) — \(Fmt.shortDay(trip.endDate)) · \(Fmt.days(trip.dayCount))")
                            .textStyle(AppFont.caption)
                    }
                    Spacer(minLength: Token.Space.s8)
                    if trip.isActive() {
                        Text("идёт").textStyle(AppFont.micro.color(Token.Status.doneText))
                    }
                }
                TGExplainer(text: .готовая(trip.transport.windowsExplainer))
            }

            PackingListCard(dog: dog, days: trip.dayCount)

            TGButton(title: "Убрать поездку", variant: .destructive,
                     size: .medium, systemImage: "trash") { isConfirmingDelete = true }
        }
        .navigationTitle(trip.destination)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Убрать поездку?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                context.delete(trip)
                try? context.save()
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи, сделанные в поездке, останутся в дневнике.")
        }
    }
}
