import SwiftUI
import SwiftData

/// Четыре вкладки, и ни одной новой за всё, что добавилось в продукт.
/// «Здоровье» появляется только при включённом лечении — у здоровой собаки
/// медицины на главном нет вовсе.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @State private var selection: Tab = .today

    enum Tab: Hashable { case today, dog, history, health, family }

    private var dog: Dog? { appState.activeDog(from: dogs) }

    /// На «Сегодня» под тостом стоит сетка действий — её высоту надо
    /// перешагнуть. На остальных вкладках хватает высоты таб-бара.
    private var toastInset: CGFloat {
        selection == .today ? 150 : 20
    }

    /// Переключить вкладку снаружи — например из шторки «Ещё», которая
    /// больше не строит навигацию сама.
    func show(_ tab: Tab) { selection = tab }

    var body: some View {
        TabView(selection: $selection) {
            TodayScreen(onOpenDog: { selection = .dog })
                .tabItem { Label("Сегодня", systemImage: "sun.horizon") }
                .tag(Tab.today)

            DogTab()
                .tabItem { Label(dog.flatMap(\.nameIfAny) ?? String(localized: "Собака"), systemImage: "pawprint") }
                .tag(Tab.dog)

            HistoryScreen()
                .tabItem { Label("История", systemImage: "calendar") }
                .tag(Tab.history)

            // Вкладку держит ПРАВО, и только оно. Решение Виктории
            // 08.10.2026: «вкладка всегда видна тому, кому можно».
            //
            // **Условие лечения снято, и возвращать его не надо.**
            // Пока оно стояло, «Здоровье» исчезало в тот день, когда
            // курс закончился, — то есть ровно тогда, когда нужен отчёт
            // врачу и история курса. Прежняя редакция этого комментария
            // объясняла, почему права тут не было вовсе (`seeMedical`
            // спрашивался в трёх местах, и все три — на «Сегодня»),
            // и под новым решением читалась наоборот: будто лечение
            // здесь обязательная половина.
            //
            // Держат это `MedicalAccessTests`: «закрыта правом И ТОЛЬКО
            // правом» краснеет на возврате `isOnTreatment`, и доказанно —
            // оба утверждения были красными до этой правки.
            // Разбор по всем пяти ролям — docs/матрица-ролей.md.
            if appState.can(.seeMedical) {
                HealthScreen()
                    .tabItem { Label("Здоровье", systemImage: "cross.case") }
                    .tag(Tab.health)
            }

            FamilyScreen()
                .tabItem { Label("Семья", systemImage: "person.2") }
                .tag(Tab.family)
        }
        // Тост подтверждения должен быть виден, а не прятаться за сеткой
        // кнопок: «нажала — и ничего не произошло» — худшее, что может
        // сделать приложение, которое просят отмечать по десять раз в день.
        .overlay(alignment: .bottom) {
            UndoToastView().padding(.bottom, toastInset)
        }
        // Возврата на «Сегодня» по концу курса здесь больше нет, и это
        // половина того же решения от 08.10.2026.
        //
        // Он был СЛЕДСТВИЕМ условия лечения: вкладка исчезала вместе
        // с выбором, и `TabView` оставался на пустом месте — человека
        // приходилось уводить. Теперь вкладку держит право, она
        // по концу курса не исчезает, и увод стал бы скачком без
        // причины — прямо из-под руки у того, кто читает историю
        // закончившегося курса.
        .onChange(of: selection) { _, tab in
            UsageLog.note(.tab, String(describing: tab), on: screen(for: tab))
        }
        .onOpenURL(perform: handle)
    }

    /// Вкладка — это и есть экран: журнал действий не должен считать
    /// переключение вкладки действием на предыдущей.
    private func screen(for tab: Tab) -> UsageLog.Screen {
        switch tab {
        case .today: .today
        case .dog: .profile
        case .history: .history
        case .health: .health
        case .family: .family
        }
    }

    /// togo://join/<token> — приглашение в семью из мессенджера.
    private func handle(_ url: URL) {
        guard url.scheme == AppIdentifiers.urlScheme else { return }
        if url.host == "join" { selection = .family }
    }
}

/// Каждая запись отменяется тостом; удаление обратимо 5 секунд.
struct UndoToastView: View {
    @Environment(AppState.self) private var appState
    /// Настройка размера текста: от неё зависит, строкой или столбцом
    /// раскладывать плашку.
    @Environment(\.dynamicTypeSize) private var размерТекста
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var appState = appState
        if let toast = appState.undo {
            // Подпись вешаем на текст, а не на всю плашку: иначе она
            // перекрывает собственное имя кнопки «Отменить», и до неё
            // не добраться ни голосом, ни тестом.
            let текст = Text(toast.message)
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.primary)
                .wraps()
            // Кнопка — только когда есть что отменять. Без этого условия
            // она стояла во всех плашках, а делала что-то в пяти
            // из пятидесяти одной: у остальных `action` нет, и нажатие
            // проваливалось в `case nil: break`.
            //
            // Это ровно тот дефект, который описан выше у `Action`
            // и там же назван починенным — у удаления. Починка стояла
            // у одной двери из пятидесяти одной.
            let отменить = Button("Отменить") { undo(toast) }
                .textStyle(AppFont.captionEmphasis)
                .foregroundStyle(Token.Status.overdueText)
                .fixedSize()
                .frame(minHeight: Token.Size.tapTarget)
            let естьЧтоОтменять = toast.action != nil

            // Знак берётся у тона, а не стоит безусловно. Галочка поверх
            // «не сохранилось» читается раньше самой фразы: глаз берёт
            // значок первым, и человек уходит уверенным, что записал.
            let знак = Image(systemName: toast.tone == .успех
                             ? "checkmark.circle.fill"
                             : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.tone == .успех
                                 ? Token.Action.doneText
                                 : Token.Status.overdueText)
                .accessibilityHidden(true)

            // Строка — пока текст и кнопка делят ширину. На крупной
            // системной настройке они её не делят: кадр 28.09 показал
            // «Записан / о · Еда» и «Отмени / ть» — перенос ВНУТРИ слова,
            // и в кнопке отмены тоже. Тогда столбцом: места вдвое
            // больше, порядок чтения тот же. Четвёртый случай одного
            // класса за день после плиток, дежурства и чипов ролей.
            Group {
                if размерТекста.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Token.Space.s8) {
                        HStack(spacing: 12) {
                            знак
                            текст
                        }
                        if естьЧтоОтменять { отменить }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        знак
                        текст
                        Spacer(minLength: 8)
                        if естьЧтоОтменять { отменить }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Token.Surface.card,
                        in: RoundedRectangle(cornerRadius: Token.Radius.sheet, style: .continuous))
            .shadow(color: Token.Ink.primary.opacity(0.12), radius: 14, y: 4)
            .padding(.horizontal, Token.Spacing.screenPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(5))
                guard appState.undo?.id == toast.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { appState.undo = nil }
            }
        }
    }

    private func undo(_ toast: AppState.UndoToast) {
        switch toast.action {
        case .removeCreated(let id):
            if let event = event(id) {
                UsageLog.note(.undo, event.kind.rawValue)
                // Мягко, тем же способом, что и остальные четыре места
                // в проекте: удаление оставляет след.
                //
                // Жёсткое `context.delete` до второго телефона не
                // доезжало вовсе — обмен слушает `inserted`/`updated`,
                // и удалённой строки в этих списках нет. Запись успевала
                // уехать, а отмена — нет: у второго человека «покормила»
                // оставалось в ленте навсегда. Мягкое удаление приходит
                // к нему обычной правкой.
                event.deletedAt = Date()
                event.deletedBy = appState.currentUserName
            }
        case .restoreDeleted(let ids):
            UsageLog.note(.undo, "restore")
            // Прогулка возвращается вместе с отметками — тем же составом,
            // каким уходила.
            for id in ids {
                guard let event = event(id) else { continue }
                event.deletedAt = nil
                event.deletedBy = nil
            }
        case nil:
            break
        }
        // Отмена — это действие человека, и если она не записалась,
        // он обязан узнать: на экране запись вернулась, в хранилище нет.
        // Возврат здесь не пишем: состояние до отмены восстановит
        // следующая загрузка из хранилища, а молчание не восстановит
        // ничего.
        if context.persist(otherwise: {}) {
            appState.undo = nil
        } else {
            Haptics.warning()
            // Через `showFailure`, а не постройкой `UndoToast` руками:
            // у структуры `tone` объявлен с умолчанием `.успех`
            // (`AppState`), и прямая постройка молча получала знак
            // успеха — на сообщении о том, что отмена НЕ сохранилась,
            // при уже сработавшей `Haptics.warning()` строкой выше.
            //
            // То есть приложение знало, что это отказ, и показывало
            // галочку. Это была ТРЕТЬЯ дверь к плашке: сторож знака
            // проверял `showUndo` и `showFailure`, а здесь не было
            // вызова вовсе — и оба его утверждения оставались зелёными.
            appState.showFailure("Отмена не сохранилась · попробуй ещё раз",
                                 action: toast.action)
        }
    }

    private func event(_ id: UUID) -> LogEvent? {
        let descriptor = FetchDescriptor<LogEvent>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
