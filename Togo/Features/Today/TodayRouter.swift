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
            case .meal:             MealSheet(dog: dog)
            case .treat:            TreatSheet(dog: dog)
            case .incident:         IncidentSheet(dog: dog)
            case .note:             NoteSheet(dog: dog)
            // Маршрут занятия оставлен ПУСТЫМ, а не удалён: `case
            // .training` живёт в перечислении маршрутов, и убрать его
            // значило бы править всех, кто по нему ветвится.
            //
            // ПРАВКА 28.10.2026: прежняя редакция этой записи кончалась
            // словами «открыть этот маршрут теперь неоткуда» — и была
            // ЛОЖНОЙ В ТОМ ЖЕ ФАЙЛЕ, двадцатью строками ниже: строка
            // «Занятие · N мин» в шторке «Ещё» ставила ровно
            // `next = .training`. Человек жал её и получал ПУСТОЙ
            // экран.
            //
            // > Утверждение «входа нет» проверяется поиском вызовов,
            // > а не памятью о том, что вход убирали. Здесь его
            // > убрали в одном месте из двух, а запись сказала
            // > «везде».
            //
            // Теперь вход снят и во втором. Пустая ветка остаётся:
            // маршрут недостижим, а `case` держит исчерпанность
            // `switch`.
            case .training:         EmptyView()
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

    /// Подпись — **`LocalizedStringKey`, а не `String`, и это замер
    /// 27.10.2026, а не вкус.**
    ///
    /// Параметр был `String`, и подстановка схлопывалась ДО того, как
    /// из неё делали ключ: `.готовая("Занятие · 3 хв")` ищет в каталоге
    /// строку целиком. Такого ключа нет — есть `Занятие · %@`, —
    /// и SwiftUI показывал подпись дословно.
    ///
    /// ```
    /// «Лакомство» · «Заметка» · «Собака со мной весь день»
    ///                        ключи каталога ЦЕЛИКОМ → переводились
    /// «Занятие · \(Fmt.minutes(…))»
    ///                        в каталоге «Занятие · %@», а искали
    ///                        «Занятие · 3 хв» → НЕ НАШЛОСЬ
    /// украинский экран       «Занятие · 3 хв» — русское слово
    ///                        и украинские минуты в одной строке
    /// ```
    ///
    /// То есть три ряда из четырёх переводились, четвёртый — нет,
    /// **и отличала их только подстановка**. `Fmt.minutes` при этом
    /// честно отдавал «3 хв»: половина строки была переведена,
    /// и именно это делало дефект невидимым — экран не выглядел русским.
    ///
    /// > **Это ровно тот класс, что описан в `LocalizedStringKey.готовая`:
    /// > поиск по каталогу выполняется ВСЕГДА, и дословно строка
    /// > показывается ровно до тех пор, пока такого ключа нет.** Здесь
    /// > ключа нет и не будет: с подстановкой он не совпадёт никогда.
    ///
    /// С `LocalizedStringKey` литерал с подстановкой собирает ключ
    /// `Занятие · %@` сам, и перевод находится у всех четырёх языков.
    /// Поймано `ScreenshotTests.test04Занятие` на партии `uk`: кадра
    /// `04-training` не было ни у одного языка, кроме русского.
    private func row(_ title: LocalizedStringKey, _ symbol: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TGListRow(title: title, systemImage: symbol, accessory: .none)
        }
        .buttonStyle(.plain)
    }
}
