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

    /// Сколько ждать, прежде чем считать нажатие вторым событием, а не
    /// повтором непонятого первого. Три секунды: собака не писает дважды
    /// за это время, а человек на морозе жмёт ещё раз именно так быстро.
    private static let повторВТечение: TimeInterval = 3

    @MainActor
    func perform() async throws -> some IntentResult {
        // Второе нажатие подряд — не вторая лужа, а непонятое первое.
        // Отзыв 22.09: «если с виджетов отмечать стул или мочу отклика
        // нет, дублируются клики». И моча, и стул повторяемые, поэтому
        // `appendMark` честно добавлял вторую отметку: в ленте выходило
        // «пописал ×2» там, где был один раз.
        if let last = ActiveSessionStore.load()?.marks.last,
           last.kind == markKind.markKind,
           Date().timeIntervalSince(last.at) < Self.повторВТечение {
            UsageLog.note(.mark, markKind.rawValue, on: .walk, outcome: .duplicate)
            return .result()
        }

        guard let session = ActiveSessionStore.appendMark(markKind.markKind) else {
            return .result()
        }
        // Нажатий с активности в журнале действий не было вовсе: самый
        // частый путь отметки не оставлял следа, и спорить о нём можно
        // было только словами.
        UsageLog.note(.mark, markKind.rawValue, on: .walk)
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

/// Закончить прогулку с экрана блокировки.
///
/// **Решение Виктории 27.10.2026 — «+ возможность закончить
/// прогулку», — и оно отменяет записанное дважды.** Круг 2 §6
/// и круг 3 §1: «„Домой" убираем, конец прогулки остаётся
/// в приложении». Довод был наш и остаётся верным: у необратимого
/// действия человек должен быть предупреждён ДО, а на блокировке
/// его никто не предупредит. Хозяин решения — она, не исполнитель.
///
/// # Что этот интент делает и чего НЕ делает
///
/// Делает: останавливает отсчёт и ставит метку
/// `закончиласьНаБлокировке`. Завершает живую активность, чтобы
/// таймер не шёл у человека, который уже дома.
///
/// **НЕ делает: записей в дневнике.** Их создаёт `WalkMode.finish`
/// через `EventLog.record`, которому нужен `ModelContext` —
/// у расширения его нет и быть не может, это другой процесс.
/// Приложение допишет их при следующем открытии и покажет итог.
///
/// > **Цена, названная прямо: между нажатием и открытием приложения
/// > прогулки в ленте нет.** Отметки при этом целы — они лежат
/// > в самой сессии. Теряются они только вместе с ней, если
/// > приложение не открыть сутки (`staleAfter`).
///
/// # Почему отдельный интент, а не третий вид отметки
///
/// `WalkMarkKind` — это ЧТО СОБАКА СДЕЛАЛА, и каждый его случай
/// повторяем: пописать можно дважды. Конец прогулки — действие
/// человека, и оно одно. Третьим случаем в том перечислении он
/// получил бы защиту от «повтора в течение трёх секунд», которая
/// для него бессмысленна, и попал бы в `markKind.markKind`, где
/// ему нет пары.
struct WalkFinishIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Закончить прогулку"
    static let description = IntentDescription("Останавливает идущую прогулку. Итог покажется в приложении.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let session = ActiveSessionStore.mutate({ сессия in
            // Идемпотентно: второе нажатие не двигает метку. На
            // блокировке человек не видит, сработало ли, и жмёт ещё
            // раз — ровно та причина, по которой у отметок стоит
            // защита от повтора.
            if сессия.закончиласьНаБлокировке == nil {
                сессия.закончиласьНаБлокировке = Date()
            }
        }) else { return .result() }

        UsageLog.note(.finish, session.kind.rawValue, on: .walk)
        for activity in Activity<WalkActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
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

    var title: String { self == .urine ? String(localized: "Пописал") : String(localized: "Стул") }
    var symbol: String { self == .urine ? "drop" : "leaf" }
}
