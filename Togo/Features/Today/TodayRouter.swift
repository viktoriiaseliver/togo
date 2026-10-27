import SwiftUI
import SwiftData

/// Куда ведёт каждая кнопка. Одно перечисление на весь главный экран —
/// так видно, что путей ровно столько, сколько кнопок.
///
/// Переехало сюда 24.10.2026 из `ActionGrid.swift`, удалённого как сирота.
/// Перечисление живое и к сиротству отношения не имело: восемь файлов
/// продуктового кода его читают (`TodayRouter`, `TodayScreen`, `TodayBottom`,
/// `ReadingTone`, `WalkMode`, `AppState`, `Подпись`), а объявление было
/// ровно одно — в удаляемом файле. Место выбрано по читателю: здесь стоит
/// единственный `switch` по всем случаям, и новый случай без ветки тут
/// не компилируется.
enum TodayRoute: Identifiable, Hashable {
    case needs
    case walk
    case walkResult
    case stool
    /// Пописал дома — отметка без прогулки.
    case urineAtHome
    case meal
    case treat
    case incident
    case note
    case training
    case more
    case dayOut
    case edit(UUID)

    var id: String {
        switch self {
        case .edit(let id): "edit-\(id)"
        default: String(describing: self)
        }
    }
}

/// Одно место, где решается, что показать по каждой кнопке главного экрана.
struct TodayRouter: View {
    let route: TodayRoute
    let dog: Dog?
    let now: Date
    var onOpenDog: () -> Void = {}

    var body: some View {
        Group {
            switch route {
            case .needs:            NeedsSheet(dog: dog)
            case .walk:             WalkModeScreen(dog: dog)
            case .walkResult:       WalkResultSheet(dog: dog)
            case .stool:            StoolSheet(dog: dog)
            case .urineAtHome:      UrineAtHomeSheet(dog: dog)
            case .meal:             MealSheet(dog: dog)
            case .treat:            TreatSheet(dog: dog)
            case .incident:         IncidentSheet(dog: dog)
            case .note:             NoteSheet(dog: dog)
            case .training:         TrainingSessionScreen(dog: dog)
            case .dayOut:           DayOutStartSheet(dog: dog)
            case .more:             MoreSheet(dog: dog, onOpenDog: onOpenDog)
            case .edit(let id):     EventEditSheet(eventID: id)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Token.Radius.sheet)
    }
}

/// Пятая кнопка. Только действия — записать то, что нужно реже, чем раз
/// в день.
///
/// Раньше отсюда же уходила навигация: «Профиль собаки» открывал экран,
/// из него питание, из него запас корма. Четыре уровня вложенности внутри
/// модальной шторки — ровно то, от чего HIG предостерегает: шторка нужна
/// для одной законченной задачи, а не для дерева разделов. Дерево переехало
/// на вкладку «Собака».
struct MoreSheet: View {
    let dog: Dog?
    /// Куда переключить вкладки, если человек всё-таки идёт в настройки собаки.
    var onOpenDog: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var next: TodayRoute?

    var body: some View {
        TGSheet(title: "Ещё", subtitle: "то, что нужно реже, чем раз в день") {
            TGCard(padding: 4) {
                VStack(spacing: 0) {
                    row("Лакомство", "sparkles") { next = .treat }
                    TGDivider()
                    row("Занятие · \(Fmt.minutes(dog?.sessionLengthMinutes ?? 3))", "target") { next = .training }
                    TGDivider()
                    row("Заметка", "text.alignleft") { next = .note }
                    TGDivider()
                    row("Собака со мной весь день", "figure.walk.motion") { next = .dayOut }
                }
                .padding(.horizontal, 12)
            }

            Button {
                dismiss()
                onOpenDog()
            } label: {
                TGCard(padding: Token.Space.s14) {
                    TGListRow(title: "Всё про собаку",
                              value: dog.map { .готовая($0.displayName) },
                              systemImage: "pawprint")
                }
            }
            .buttonStyle(.plain)
            TGExplainer(text: "Питание, уход, документы и «если что-то случилось» живут на вкладке собаки — туда два тапа с любого экрана.")
        }
        .presentationDetents([.medium])
        .sheet(item: $next) { route in
            TodayRouter(route: route, dog: dog, now: Date())
        }
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TGListRow(title: .готовая(title), systemImage: symbol, accessory: .none)
        }
        .buttonStyle(.plain)
    }
}
