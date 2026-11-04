import SwiftUI
import SwiftData

/// Цвет числа «хватит на N дней» по лестнице запаса.
///
/// Лестница берётся у `PillSupplyAdvisor` — одна на корм и таблетки,
/// с порогами 7 и 3 (07.10.2026). До этого корм красился по булеву
/// `needsRestock`, и «кончается через неделю» было того же цвета,
/// что «кончается завтра».
///
/// Готовое `Level.цветТекста` со экрана таблеток намеренно НЕ зовётся:
/// там у `.ok` цвет «сделано», и для строки списка это была бы
/// подтверждающая зелень на ровном месте. Расходится палитра, а не
/// правило — правило одно и спрашивается, а не повторяется.
private func цветЗапаса(_ level: PillSupplyAdvisor.Level) -> Color {
    switch level {
    case .ok: Token.Ink.primary
    case .low: Token.Status.stockLowText
    case .urgent, .out: Token.Status.overdueText
    }
}

/// Строка одного корма в запасе.
struct StockRow: View {
    let stock: FoodStock
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Image(systemName: stock.kind.symbol)
                .font(.system(size: Token.Size.iconMd, weight: .medium))
                .foregroundStyle(Token.Ink.silhouette)
                .frame(width: Token.Space.s24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(stock.brand.isEmpty ? stock.kind.title : stock.brand)
                    .textStyle(AppFont.bodyEmphasis)
                Text(stock.summary(at: now))
                    .textStyle(AppFont.caption)
                    .wraps()
            }
            Spacer(minLength: Token.Space.s8)
            VStack(alignment: .trailing, spacing: Token.Space.s2) {
                Text(stock.daysLeft(at: now).map { Fmt.days($0) } ?? "—")
                    .textStyle(AppFont.numeric(15).color(цветЗапаса(stock.level(at: now))))
                Text("хватит").textStyle(AppFont.micro)
            }
        }
        .frame(minHeight: 54)
    }
}

/// Запас корма: чем кормят, в какой фасовке и сколько осталось.
///
/// Сухой берут мешками, влажный — банками по 100–500 граммов, и очень часто
/// дают и то и другое. Поэтому кормов может быть несколько, и у каждого
/// своя фасовка и своя дневная доля.
struct FoodStockScreen: View {
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    /// Запросом, а не через связь собаки: только что вставленный корм
    /// в обратной связи появляется не сразу, и список остаётся пустым —
    /// человек жмёт «Добавить», и «ничего не происходит».
    @Query(sort: \FoodStock.kindRaw) private var allStocks: [FoodStock]

    @State private var editing: FoodStock?
    @State private var isAdding = false

    private var stocks: [FoodStock] {
        allStocks.filter { $0.dog?.persistentModelID == dog.persistentModelID }
    }

    private var canEdit: Bool { appState.can(.editProfile) }
    private var total: Int { stocks.map(\.gramsPerDay).reduce(0, +) }

    var body: some View {
        TGScreen {
            CinemaHeader("Чем кормим", отступы: false)
            if stocks.isEmpty {
                EmptyStateCard(
                    subject: .foodStock,
                    title: "Корм пока не записан",
                    message: "Добавь то, чем кормишь: сухой считается мешками, влажный — банками. Даёшь оба — добавь оба и укажи граммы в день на каждый.",
                    actionTitle: canEdit ? "Добавить корм" : nil,
                    action: canEdit ? { isAdding = true } : nil
                )
            } else {
                // Заголовок «чем кормим» над карточкой снят 29.10.2026:
                // он повторял имя экрана строкой ниже шапки «Чем кормим».
                TGCard(spacing: 0) {
                    ForEach(stocks) { stock in
                        Button { if canEdit { editing = stock } } label: {
                            StockRow(stock: stock, now: .now)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if stock.id != stocks.last?.id { TGDivider() }
                    }
                }

                balanceCard
                restockCard
            }
        } bottom: {
            if canEdit && !stocks.isEmpty {
                TGButton(title: "Добавить корм", variant: .secondary,
                         size: .medium, systemImage: "plus") { isAdding = true }
            }
        }
        .navigationTitle("Чем кормим")
        .cinemaScreen(экран: .sub("feeding"))
        .usageScreen(.foodStock)
        .sheet(isPresented: $isAdding) { FoodStockEditorSheet(dog: dog) }
        .sheet(item: $editing) { stock in FoodStockEditorSheet(stock: stock, dog: dog) }
    }

    /// Сходится ли сумма по кормам с дневной нормой.
    ///
    /// Показывается только при смешанном кормлении. Когда корм один,
    /// его расход равен норме по построению — и карточка повторяла бы
    /// число, которое человек только что видел на «Питании».
    @ViewBuilder
    private var balanceCard: some View {
        if stocks.count > 1 || dog.stocks.contains(where: { $0.kind == .wet }) {
            TGCard {
                if stocks.count > 1 {
                    HStack {
                        Text("Выходит в день").textStyle(AppFont.body)
                        Spacer()
                        Text("\(total) г").textStyle(AppFont.numeric(20))
                    }
                    if dog.dailyGrams > 0, total != dog.dailyGrams {
                        TGBanner(
                            tone: .waiting,
                            title: total > dog.dailyGrams ? "Больше нормы" : "Меньше нормы",
                            subtitle: "Норма — \(dog.dailyGrams) г в день, по кормам выходит \(total) г. Так бывает: поправь или раскладку здесь, или саму норму на «Питании».",
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                }
                if dog.stocks.contains(where: { $0.kind == .wet }) {
                    TGExplainer(text: .готовая(FoodKind.wet.caution ?? ""))
                }
            }
        }
    }

    private var restockCard: some View {
        TGCard {
            TGSectionHeader(title: "купить на месяц",
                            subtitle: "чтобы не переводить собаку на другой корм в спешке")
            ForEach(stocks) { stock in
                let packs = stock.packsNeeded(forDays: FoodPlanner.planningDays)
                HStack {
                    Text(stock.brand.isEmpty ? stock.kind.title : stock.brand)
                        .textStyle(AppFont.body)
                    Spacer(minLength: Token.Space.s8)
                    Text(packs == 0
                         ? "хватает"
                         : "\(packs) \(stock.kind.unitName(count: Double(packs))) по \(stock.kind.packLabel(stock.packGrams))")
                        .textStyle(AppFont.captionEmphasis.color(
                            packs == 0 ? Token.Action.doneText : Token.Ink.primary
                        ))
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: Token.Size.tapTarget)
            }
        }
    }
}

/// Форма корма: тип, фасовка, остаток, дневная доля.
struct FoodStockEditorSheet: View {
    @Environment(AppState.self) private var appState
    var stock: FoodStock?
    let dog: Dog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allStocks: [FoodStock]

    private var siblings: [FoodStock] {
        allStocks.filter {
            $0.dog?.persistentModelID == dog.persistentModelID
                && $0.persistentModelID != stock?.persistentModelID
        }
    }

    /// Сколько дневной нормы уже разобрали другие корма.
    private var otherGramsPerDay: Int { siblings.map(\.gramsPerDay).reduce(0, +) }

    /// Корм у собаки один — а значит, спрашивать «сколько в день»
    /// второй раз незачем: это ровно дневная норма из режима питания.
    /// Пока спрашивали, два числа расходились молча, и обратный отсчёт
    /// запаса считал не по той цифре.
    private var isOnlyFood: Bool { siblings.isEmpty }

    /// Сколько граммов уедет в запись — **одна величина на условие
    /// кнопки, на обе арифметики карточки и на сохранение**.
    ///
    /// Заведена, чтобы условие кнопки не считало своё: иначе кнопка
    /// бывала выключена при готовой к записи величине и наоборот.
    /// **А повторяли её при этом три места** (замер 28.10.2026):
    /// `save()`, `draftStock` и превью «хватит на · кончится · купить
    /// на месяц». Первые два совпадали посимвольно, третье считало
    /// по голому `gramsPerDay` — и у единственного корма это другое
    /// число. Теперь зовут сюда все; номера строк в этом разборе
    /// намеренно не названы — они устаревают быстрее правила.
    private var кСохранению: Int { isOnlyFood ? dog.dailyGrams : gramsPerDay }

    /// Сколько нормы осталось нераспределённым.
    private var unassignedGrams: Int { dog.dailyGrams - otherGramsPerDay - gramsPerDay }

    @State private var kind: FoodKind = .dry
    @State private var brand = ""
    @State private var packGrams = 3000
    @State private var customPack = false
    @State private var packsLeft = 1.0
    @State private var gramsPerDay = 0
    @State private var isConfirmingDelete = false
    @State private var loaded = false

    private var isNew: Bool { stock == nil }

    var body: some View {
        TGSheet(title: isNew ? "Корм" : .готовая(brand.isEmpty ? kind.title : brand),
                subtitle: "фасовка и остаток считаются отдельно для каждого корма",
                closeTitle: isNew ? "Отмена" : "Закрыть",
                hasUnsavedChanges: isNew && !brand.trimmingCharacters(in: .whitespaces).isEmpty) {
            kindCard
            packCard
            amountCard
            if let caution = kind.caution {
                TGExplainer(text: .готовая(caution))
            }
            if !isNew {
                TGButton(title: "Убрать корм", variant: .destructive,
                         size: .medium, systemImage: "trash") { isConfirmingDelete = true }
            }
        } footer: {
            // **Условие кнопки смотрит на ту же величину, что и `save()`.**
            //
            // Было `gramsPerDay > 0` — локальный счётчик, который при
            // единственном корме не правится ничем: степпер в этой ветке
            // не рисуется вовсе (`:340`), а сохранение берёт
            // `dog.dailyGrams` (`:321`, `:424`).
            //
            // Значит у человека с одним кормом и нулевой нормой кнопка
            // была выключена НАВСЕГДА, и органа, который её включит,
            // на экране не было ни одного. Выход — только «назад».
            //
            // > **Условие и действие смотрели на разные величины.**
            // > Кнопка спрашивала про то, чего в этой ветке не бывает.
            //
            // И правило дизайна (круг 5, п. 1): выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Поэтому ниже — строка, а не молчание.
            VStack(spacing: Token.Space.s8) {
                if кСохранению == 0 {
                    Text(isOnlyFood
                         ? "Сначала укажи дневную норму — она в «Питании и режиме»"
                         : "Поставь, сколько этого корма в день")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: isNew ? "Добавить" : "Сохранить",
                         isEnabled: кСохранению > 0) { save() }
            }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Убрать корм?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                if let stock { context.delete(stock) }
                // Удаление без сохранения закрывало шторку как успех
                // (аудит 28.10.2026). Откатить удаление нечем — говорим правду.
                guard context.persistNothingToUndo() else {
                    Haptics.warning()
                    appState.showFailure(String(localized: "Не удалилось · проверь после перезапуска"))
                    return
                }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи о кормлениях останутся — уйдёт только расчёт запаса.")
        }
    }

    private var kindCard: some View {
        TGCard {
            TGSectionHeader(title: "какой корм")
            TGChipGroup(items: FoodKind.allCases, title: \.title,
                        isSelected: { $0 == kind }) { newKind in
                kind = newKind
                // У сухого и влажного разные фасовки: подставляем самую ходовую.
                if !customPack { packGrams = newKind == .wet ? 400 : 3000 }
                Haptics.tap()
            }
            LabeledField(label: "Марка") {
                TextField("необязательно", text: $brand)
            }
        }
    }

    private var packCard: some View {
        TGCard {
            TGSectionHeader(title: "фасовка",
                            subtitle: kind == .wet ? "банка или пауч" : "мешок")
            TGChipGroup(
                items: kind.commonPackSizes,
                title: { kind.packLabel($0) },
                isSelected: { $0 == packGrams && !customPack },
                minimumWidth: 84
            ) { size in
                packGrams = size
                customPack = false
                Haptics.tap()
            }
            Toggle(isOn: $customPack) {
                Text("Своя фасовка").textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)
            if customPack {
                Stepper(value: $packGrams, in: 20...20000, step: kind == .wet ? 10 : 500) {
                    HStack {
                        Text("Сколько в упаковке").textStyle(AppFont.body)
                        Spacer()
                        Text(kind.packLabel(packGrams)).textStyle(AppFont.numeric(17))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
            }
        }
    }

    /// Сходится ли раскладка с нормой. Смешанное кормление — это всегда
    /// «столько-то сухого плюс банка сверху», и человек должен видеть,
    /// что в сумме получается ровно норма, а не считать в уме.
    @ViewBuilder
    private var splitRow: some View {
        if dog.dailyGrams > 0 {
            HStack(alignment: .top) {
                Text("Из \(dog.dailyGrams) г в день").textStyle(AppFont.caption)
                Spacer(minLength: Token.Space.s8)
                Text(splitStatus)
                    .textStyle(AppFont.caption.color(unassignedGrams == 0 ? Token.Action.doneText : Token.Status.waitingText))
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: Token.Size.tapTarget)
        } else {
            // Делить нечего: `unassignedGrams` это `норма − разложенное`,
            // и при ненаписанной норме он выходил отрицательным — строка
            // говорила «перебор на столько-то», то есть упрекала человека
            // числом, выведенным из нашего же пробела.
            Text("Из чего делить, приложение не знает: дневная норма не записана.")
                .textStyle(AppFont.caption)
                .wraps()
                .frame(minHeight: Token.Size.tapTarget)
        }
    }

    private var splitStatus: String {
        switch unassignedGrams {
        case 0: String(localized: "норма разложена полностью")
        case let left where left > 0: String(localized: "осталось разложить \(left) г")
        case let over: String(localized: "перебор на \(-over) г")
        }
    }

    /// Черновик для арифметики: те же поля, что и в форме, но считает
    /// их модель, а не экран.
    private var draftStock: FoodStock {
        FoodStock(kind: kind, brand: brand, packGrams: packGrams,
                  packsLeft: packsLeft, gramsPerDay: кСохранению)
    }

    private var amountCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "сколько есть и сколько уходит")
            Stepper(value: $packsLeft, in: 0...200, step: kind == .wet ? 1 : 0.5) {
                HStack {
                    Text("Осталось").textStyle(AppFont.body)
                    Spacer()
                    // `Fmt.decimal`, а не `String(format: "%.1f")`:
                    // у `String(format:)` без локали разделитель всегда
                    // POSIX, и в русском выходило `2.5 мешка` — точка
                    // рядом с `4,7 кг` на соседнем экране. Переводить
                    // тут нечего: число и единица, слов нет.
                    Text(kind == .wet
                         ? "\(Int(packsLeft)) \(kind.unitName(count: packsLeft))"
                         : "\(Fmt.decimal(packsLeft)) \(kind.unitName(count: packsLeft))")
                        .textStyle(AppFont.numeric(17))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)

            TGDivider()
            if isOnlyFood {
                // Корм один — цифра берётся из режима питания и правится там.
                // Два места для одного числа и были главной путаницей.
                HStack {
                    Text("В день").textStyle(AppFont.body)
                    Spacer()
                    // Прочерк, а не «0 г»: это зеркало дневной нормы,
                    // и ноль в нём читался как «кормить нечем».
                    Text(verbatim: dog.dailyGrams > 0 ? String(localized: "\(dog.dailyGrams) г") : "—")
                        .textStyle(AppFont.numeric(17))
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: dog.dailyGrams > 0
                    ? "Это дневная норма из режима питания — здесь её не дублируем. Добавишь второй корм, и появится, как поделить норму между ними."
                    : "Это зеркало дневной нормы, а она не записана. Запиши её в режиме питания — и расход запаса начнёт считаться.")
            } else {
                Stepper(value: $gramsPerDay, in: 0...2000, step: kind == .wet ? 25 : 5) {
                    HStack {
                        Text("В день").textStyle(AppFont.body)
                        Spacer()
                        Text("\(gramsPerDay) г").textStyle(AppFont.numeric(17))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                splitRow
            }

            // Ту же арифметику считала и модель, и этот экран — своими
            // руками. Считает теперь одна модель.
            if kind == .wet, let perDay = draftStock.packsPerDay {
                TGDivider()
                HStack {
                    Text("Это примерно").textStyle(AppFont.body)
                    Spacer()
                    // **Ключ `%.1f %@ в день` лежал в каталоге
                    // переведённым на пять языков и не читался ни разу**
                    // (замер 28.10.2026). У записи стоит
                    // `extractionState: manual`, а в поле `comment` —
                    // имя `amountCard`, то есть её завели рукой ровно
                    // под эту строку. Читателя не было: голый
                    // `String(format:)` в каталог не ходит по
                    // устройству, и француз видел здесь «в день».
                    //
                    // Это четвёртая форма «механизма без входа»:
                    // имя есть, значение есть, вызова по имени нет.
                    // Образец правильной сборки лежал через файл —
                    // `FoodStock.swift:160`.
                    //
                    // `locale:` обязателен отдельно от каталога: он
                    // отвечает за разделитель у `%.1f`, а не за слова.
                    Text(String(format: String(localized: "%.1f %@ в день"),
                                locale: .current,
                                perDay, kind.unitName(count: perDay)))
                        .textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                }
                .frame(minHeight: Token.Size.tapTarget)
            }

            // Третий черновик той же записи на этом экране стоял здесь
            // со СВОИМ расходом — голым `gramsPerDay` вместо
            // `кСохранению` (замер 28.10.2026). У единственного корма
            // шаговика нет, и число в нём остаётся от прошлого захода:
            // строка «норма не записана, расход не считается» стояла
            // ровно над «хватит на 12 дней», посчитанными по той самой
            // норме, которой нет. Черновик теперь один на всю карточку.
            let preview = draftStock
            if let days = preview.daysLeft() {
                TGDivider()
                РядЧисел {
                    TGStat(value: Fmt.days(days), caption: "хватит на", size: 17)
                    TGStat(value: preview.runsOutOn().map(Fmt.shortDay) ?? "—",
                           caption: "кончится", size: 17)
                    TGStat(value: "\(preview.packsNeeded(forDays: FoodPlanner.planningDays))",
                           caption: "купить на месяц", size: 17)
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        if let stock {
            kind = stock.kind
            brand = stock.brand
            packGrams = stock.packGrams
            customPack = !stock.kind.commonPackSizes.contains(stock.packGrams)
            packsLeft = stock.packsLeft
            gramsPerDay = stock.gramsPerDay
        } else {
            // Подставляем всю дневную норму: у большинства корм один.
            // Первый корм забирает всю дневную норму, следующий — остаток:
            // при смешанном кормлении человеку не надо считать в уме.
            gramsPerDay = max(0, dog.dailyGrams - otherGramsPerDay)
        }
        loaded = true
    }

    /// Марка корма едет в профиль собаки: это единственное место,
    /// где её теперь вводят, а подпись к кормлению её ждёт.
    private func syncBrand() {
        if let brand = FeedingMigration.primaryBrand(of: dog) { dog.foodBrand = brand }
    }

    private func save() {
        let target = stock ?? FoodStock(kind: kind, brand: brand, packGrams: packGrams,
                                        packsLeft: packsLeft, gramsPerDay: gramsPerDay)
        target.kind = kind
        target.brand = brand
        target.packGrams = packGrams
        target.packsLeft = packsLeft
        // У единственного корма расход равен дневной норме: отдельного
        // числа для него не спрашиваем и не храним расхождение.
        // Выражение не повторяется — `кСохранению` для того и заведено.
        target.gramsPerDay = кСохранению
        if stock == nil {
            target.openedAt = Date()
            target.dog = dog
            context.insert(target)
        }
        // Пересчёт остатка — это новая точка отсчёта: человек только что
        // посмотрел, сколько у него банок. Без неё расход считался бы
        // от старой даты и уводил цифру в минус.
        target.countedAt = Date()
        // Сохраняем сразу: иначе связь применяется не мгновенно,
        // и человек возвращается на экран, где ничего не изменилось.
        syncBrand()
        guard context.persist(otherwise: {}) else {
            // Была только вибрация.
            Haptics.warning()
            appState.showFailure(
                String(localized: "Запас не сохранился · нажми ещё раз"))
            return
        }
        Haptics.success()
        dismiss()
    }
}
