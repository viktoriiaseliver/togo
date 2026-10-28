import SwiftUI
import SwiftData

/// Лента дня списком — редакция со свайпом из хендоффа
/// (`design_handoff_togo_ios28`, «Рекомендации» 3: «Лента — `List`
/// со `swipeActions`, не кастомный свайп»).
///
/// ## Почему отдельным типом, а не правкой `DayTimeline`
///
/// `List` внутри `ScrollView` не живёт: своей высоты он не считает,
/// и строки либо схлопываются, либо уезжают в бесконечность. Оба
/// нынешних хозяина ленты держат её именно там — `TodayScreen.swift:123`
/// и `TGSheet` в `HistoryScreen`. Поставить `List` прямо в `DayTimeline`
/// значило бы положить красное всем, и починить это может только
/// владелец хозяина: `ScrollView` вокруг `деньПозади` должен уйти,
/// а лента — стать своим скроллом.
///
/// Поэтому строки общие (`DayTimelineRow`, `DayTimelineGapRow`,
/// `DayTimelineMarkRow`), а контейнеров два. Это сознательный долг,
/// а не вторая реализация: разойтись строкам негде, они одни.
///
/// ## Свайп — настоящий, и это сказано замером
///
/// В проекте `.swipeActions` встречался вторым местом — `CareScreen.swift:329`,
/// — но стоял на строке внутри `TGCard { ForEach … }`, то есть **вне
/// `List`**, где модификатор не делает ничего. Замер 22.10.2026:
/// `List` в `CareScreen.swift` нет ни одного. Это ровно «механизм без
/// входа»: модификатор написан, выглядит рабочим и не срабатывал ни разу.
/// Здесь он внутри `List`, и это единственное место в проекте, где свайп
/// может сработать.
///
/// **Тот мёртвый модификатор снят 24.10.2026** (замер повторён в тот же
/// день: `List` в `CareScreen.swift` — 0 при живом контроле
/// `DayTimelineList.swift` — 9). Следствие для этого файла важнее самой
/// уборки: довод «в проекте такое уже есть» держать больше нечем.
/// Единственное вхождение `.swipeActions` в продуктовом коде — строка 71
/// ниже, **в этом самом типе, который сам ещё не подключён**. То есть
/// рабочего свайпа в приложении сегодня нет ни одного, и хендофф
/// исполнен ровно на ноль поверхностей.
///
/// Отдельно о том, как это прожило двое суток: дефект был НАЙДЕН 22.10
/// и записан — но записан ЗДЕСЬ, в файле-соседе, а не рядом с предметом
/// в `CareScreen`. Тот, кто читал `CareScreen`, предупреждения не видел;
/// тот, кто читал эту голову, правил не тот файл.
struct DayTimelineList: View {
    let events: [LogEvent]
    let now: Date
    var showsAuthor: Bool = false
    /// В прошедшем дне «сейчас» не место: он давно прошёл.
    var showsNow: Bool = true
    var onEdit: (LogEvent) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    /// Порог промежутка — у соседа, а не свой: решение одно
    /// (`DayTimeline.gapThreshold`), и двух копий у него быть не должно.
    private static var gapThreshold: TimeInterval { DayTimeline.gapThreshold }

    private var blocks: [TimelineBlock] { TimelineBuilder.blocks(events) }

    private var sinceLastEntry: TimeInterval? {
        TimelineBuilder.timeIndoorsNow(blocks, now: now, threshold: Self.gapThreshold)
    }

    var body: some View {
        List {
            if blocks.isEmpty {
                EmptyDayState().строкаЛенты()
            } else {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    if let indoors = TimelineBuilder.timeIndoors(
                        before: index, in: blocks, threshold: Self.gapThreshold) {
                        DayTimelineGapRow(interval: indoors).строкаЛенты()
                    }

                    DayTimelineRow(block: block, showsAuthor: showsAuthor)
                        .строкаЛенты()
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(block.event) }
                        // `allowsFullSwipe: false` нарочно: полный смах
                        // удаляет, не показав кнопки, а хендофф рисует
                        // обе — «Изменить» и «Удалить». У необратимого
                        // на вид действия предупреждение адресовано тому,
                        // кто его совершает, и показать надо ДО.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Первой объявлена та, что встанет с краю:
                            // в прототипе «Удалить» крайняя справа.
                            Button(role: .destructive) { удалить(block) } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button { onEdit(block.event) } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                            .tint(Token.Surface.control)
                        }
                        // Свайпом озвучка не пользуется: ей нужны именованные
                        // действия. Без этого «Удалить» существует только
                        // для тех, кто видит экран.
                        .accessibilityActions {
                            Button("Изменить") { onEdit(block.event) }
                            Button("Удалить") { удалить(block) }
                        }

                    ForEach(block.markGroups) { group in
                        DayTimelineMarkRow(group: group)
                            .строкаЛенты()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onEdit(group.count == 1 ? group.representative : block.event)
                            }
                    }
                }

                if showsNow {
                    NowMarker(now: now, sinceLast: sinceLastEntry).строкаЛенты()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, Token.Size.tapTarget)
    }

    /// Удаление — **мягкое**, как в остальных местах проекта.
    ///
    /// Жёсткое `context.delete` до второго телефона не доезжает вовсе:
    /// обмен слушает `inserted`/`updated`, и удалённой строки в этих
    /// списках нет. Запись успевала уехать, а удаление — нет, и у второго
    /// человека «покормила» оставалось в ленте навсегда. Мягкое приходит
    /// к нему обычной правкой.
    ///
    /// Прогулка уходит вместе со своими отметками: они записаны как одно
    /// целое, и раньше их приходилось убирать по одной.
    ///
    /// > **Это пятое место с тем же телом.** Старший близнец —
    /// > `LogSheets.swift:550`, он `private`, и свести их в одно —
    /// > отдельная работа через владельца `Features/Log`. Пока они
    /// > разойдутся молча, и единственная защита от этого — строка здесь.
    private func удалить(_ block: TimelineBlock) {
        let когда = Date()
        let кто = appState.currentUserName
        // Уже удалённые не трогаем: иначе отмена вернула бы к жизни то,
        // что человек убрал раньше и другим действием.
        let убираем = (block.marks + [block.event]).filter { $0.deletedAt == nil }
        guard !убираем.isEmpty else { return }

        for цель in убираем {
            цель.deletedAt = когда
            цель.deletedBy = кто
        }
        guard context.persist(otherwise: {
            for цель in убираем {
                цель.deletedAt = nil
                цель.deletedBy = nil
            }
        }) else {
            Haptics.warning()
            // Через `showFailure`, а не постройкой `UndoToast` руками:
            // у структуры `tone` объявлен с умолчанием `.успех`, и прямая
            // постройка молча поставила бы галочку на сообщении об отказе.
            return appState.showFailure("Удаление не сохранилось · попробуй ещё раз")
        }
        Haptics.warning()
        UsageLog.note(.delete, block.event.kind.rawValue)
        // `showUndoRestore`, а не `showUndo`: кнопка должна ВЕРНУТЬ
        // запись, а не убрать её. Пока удаление звали через `showUndo`
        // без `eventID`, кнопка «Отменить» стояла и не делала ничего —
        // при подписи «удаление обратимо пять секунд».
        appState.showUndoRestore(убираем.count == 1
                                 ? String(localized: "Удалено · \(block.event.kind.title)")
                                 : String(localized: "Удалена прогулка и \(убираем.count - 1) отметки"),
                                 eventIDs: убираем.map(\.id))
    }
}

private extension View {
    /// Строка ленты во всю ширину на сплошной `surface-card`.
    ///
    /// Хендофф: «Сплошные строки `surface-card` (не стекло — сквозь стекло
    /// просвечивали кнопки свайпа)». Отступы строки обнуляются, потому что
    /// свои она ставит сама, — иначе под кнопкой свайпа оставалась бы
    /// полоса фона списка.
    func строкаЛенты() -> some View {
        self.listRowBackground(Token.Surface.card)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}
