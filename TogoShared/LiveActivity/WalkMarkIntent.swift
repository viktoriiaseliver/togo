import AppIntents
import ActivityKit

/// Отметка прямо с заблокированного экрана, пока идёт прогулка.
///
/// Это и есть ответ на «отмечать не доставая телефон». Кнопка громкости
/// для этого не годится — Apple разрешает перехватывать её только затвору
/// камеры, — а вот кнопки на живой активности разрешены и работают ровно
/// там, где нужно: телефон в кармане, собака присела, экран заблокирован.
///
/// `LiveActivityIntent` выполняется в процессе приложения, а не расширения.
/// Это важно: у Того нет общей группы (её не выдаёт бесплатная команда
/// разработчика), и до дневника из расширения было бы не дотянуться.
///
/// Отметка кладётся в сохранённую прогулку, а не в копию в памяти:
/// приложение в этот момент в фоне, и его копия может быть старше.
/// В ленту всё уедет, когда прогулка закончится, — как и с отметками,
/// поставленными руками.
struct WalkMarkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Отметить на прогулке"
    static let description = IntentDescription("Ставит отметку на идущей прогулке.")
    static let openAppWhenRun = false

    @Parameter(title: "Что отметить")
    var markKind: WalkMarkKind

    init() {}

    init(_ kind: WalkMarkKind) {
        self.markKind = kind
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let session = ActiveSessionStore.appendMark(markKind.markKind) else {
            return .result()
        }
        await refreshActivity(with: session)
        return .result()
    }

    /// Показать на самой активности, что отметка встала.
    ///
    /// Без этого нажатие проходит вслепую: экран заблокирован, приложение
    /// не открывается, и человек не знает, засчиталось или нет.
    @MainActor
    private func refreshActivity(with session: ActiveSession) async {
        let state = WalkActivityAttributes.ContentState(
            startedAt: session.startedAt,
            tally: session.marks.isEmpty ? nil : session.tally
        )
        for activity in Activity<WalkActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}

/// Что можно отметить с экрана блокировки.
///
/// Список короткий намеренно: на морозе одной рукой человек попадёт
/// в две большие кнопки, а не в восемь маленьких. Остальное — в приложении.
nonisolated enum WalkMarkKind: String, AppEnum, CaseIterable {
    case urine
    case stool

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Отметка")

    static let caseDisplayRepresentations: [WalkMarkKind: DisplayRepresentation] = [
        .urine: DisplayRepresentation(title: "Пописал", image: .init(systemName: "drop")),
        .stool: DisplayRepresentation(title: "Стул", image: .init(systemName: "leaf")),
    ]

    var markKind: ActiveSession.Mark.Kind {
        switch self {
        case .urine: .urine
        case .stool: .stool
        }
    }

    var title: String { self == .urine ? "Пописал" : "Стул" }
    var symbol: String { self == .urine ? "drop" : "leaf" }
}
