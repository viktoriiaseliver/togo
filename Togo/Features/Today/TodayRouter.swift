import SwiftUI
import SwiftData

/// Одно место, где решается, что показать по каждой кнопке главного экрана.
struct TodayRouter: View {
    let route: TodayRoute
    let dog: Dog?
    let now: Date

    var body: some View {
        Group {
            switch route {
            case .needs:            NeedsSheet(dog: dog)
            case .walk:             WalkStartSheet(dog: dog)
            case .walkResult:       WalkResultSheet(dog: dog)
            case .stool:            StoolSheet(dog: dog)
            case .meal:             MealSheet(dog: dog)
            case .water:            WaterSheet(dog: dog)
            case .treat:            TreatSheet(dog: dog)
            case .incident:         IncidentSheet(dog: dog)
            case .note:             NoteSheet(dog: dog)
            case .training:         TrainingSessionScreen(dog: dog)
            case .care:             CareScreen(dog: dog)
            case .more:             MoreSheet(dog: dog)
            case .edit(let id):     EventEditSheet(eventID: id)
            }
        }
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Token.Radius.sheet)
    }
}

/// Пятая кнопка. Всё, что нужно реже, чем раз в день.
struct MoreSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @State private var next: TodayRoute?

    var body: some View {
        TGSheet(title: "Ещё", subtitle: "то, что нужно реже, чем раз в день") {
            TGCard(padding: 4) {
                VStack(spacing: 0) {
                    row("Лакомство", "sparkles") { next = .treat }
                    TGDivider()
                    row("Занятие · \(dog?.sessionLengthMinutes ?? 3) минуты", "target") { next = .training }
                    TGDivider()
                    row("Заметка", "text.alignleft") { next = .note }
                    TGDivider()
                    row("Уход и напоминания", "scissors") { next = .care }
                }
                .padding(.horizontal, 12)
            }
            NavigationLink { ProfileScreen(dog: dog) } label: {
                TGCard(padding: 14) {
                    TGListRow(title: "Профиль собаки", value: dog?.name, systemImage: "pawprint")
                }
            }
            .buttonStyle(.plain)
        }
        .presentationDetents([.medium])
        .sheet(item: $next) { route in
            TodayRouter(route: route, dog: dog, now: Date())
        }
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TGListRow(title: title, systemImage: symbol)
        }
        .buttonStyle(.plain)
    }
}
