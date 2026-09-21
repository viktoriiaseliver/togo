import SwiftUI
import SwiftData

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
                    .textStyle(AppFont.numeric(15).color(
                        stock.needsRestock(at: now) ? Token.Status.waitingText : Token.Ink.primary
                    ))
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
            if stocks.isEmpty {
                EmptyStateCard(
                    systemImage: "shippingbox",
                    title: "Корм пока не записан",
                    message: "Добавь то, чем кормишь: сухой считается мешками, влажный — банками. Даёшь и то и другое — добавь оба и укажи, сколько граммов в день приходится на каждый.",
                    actionTitle: canEdit ? "Добавить корм" : nil,
                    action: canEdit ? { isAdding = true } : nil
                )
            } else {
                TGCard(spacing: 0) {
                    TGSectionHeader(title: "чем кормим")
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
        .usageScreen(.foodStock)
        .navigationBarTitleDisplayMode(.large)
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
                            subtitle: "Норма — \(dog.dailyGrams) г в день, по кормам выходит \(total) г. Это не ошибка: поправить можно или раскладку здесь, или саму норму на «Питании».",
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                }
                if dog.stocks.contains(where: { $0.kind == .wet }) {
                    TGExplainer(text: FoodKind.wet.caution ?? "")
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
        TGSheet(title: isNew ? "Корм" : (brand.isEmpty ? kind.title : brand),
                subtitle: "фасовка и остаток считаются отдельно для каждого корма",
                closeTitle: isNew ? "Отмена" : "Закрыть",
                hasUnsavedChanges: isNew && !brand.trimmingCharacters(in: .whitespaces).isEmpty) {
            kindCard
            packCard
            amountCard
            if let caution = kind.caution {
                TGExplainer(text: caution)
            }
            if !isNew {
                TGButton(title: "Убрать корм", variant: .destructive,
                         size: .medium, systemImage: "trash") { isConfirmingDelete = true }
            }
        } footer: {
            TGButton(title: isNew ? "Добавить" : "Сохранить", isEnabled: gramsPerDay > 0) { save() }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Убрать корм?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                if let stock { context.delete(stock) }
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
        HStack(alignment: .top) {
            Text("Из \(dog.dailyGrams) г в день").textStyle(AppFont.caption)
            Spacer(minLength: Token.Space.s8)
            Text(splitStatus)
                .textStyle(AppFont.caption.color(unassignedGrams == 0 ? Token.Action.doneText : Token.Status.waitingText))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    private var splitStatus: String {
        switch unassignedGrams {
        case 0: "норма разложена полностью"
        case let left where left > 0: "осталось разложить \(left) г"
        case let over: "перебор на \(-over) г"
        }
    }

    /// Черновик для арифметики: те же поля, что и в форме, но считает
    /// их модель, а не экран.
    private var draftStock: FoodStock {
        FoodStock(kind: kind, brand: brand, packGrams: packGrams,
                  packsLeft: packsLeft,
                  gramsPerDay: isOnlyFood ? dog.dailyGrams : gramsPerDay)
    }

    private var amountCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "сколько есть и сколько уходит")
            Stepper(value: $packsLeft, in: 0...200, step: kind == .wet ? 1 : 0.5) {
                HStack {
                    Text("Осталось").textStyle(AppFont.body)
                    Spacer()
                    Text(kind == .wet
                         ? "\(Int(packsLeft)) \(kind.unitName(count: packsLeft))"
                         : String(format: "%.1f %@", packsLeft, kind.unitName(count: packsLeft)))
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
                    Text("\(dog.dailyGrams) г").textStyle(AppFont.numeric(17))
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Это дневная норма из режима питания — здесь её не дублируем. Добавишь второй корм, и появится, как поделить норму между ними.")
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
                    Text(String(format: "%.1f %@ в день", perDay, kind.unitName(count: perDay)))
                        .textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                }
                .frame(minHeight: Token.Size.tapTarget)
            }

            let preview = FoodStock(kind: kind, packGrams: packGrams,
                                    packsLeft: packsLeft, gramsPerDay: gramsPerDay)
            if let days = preview.daysLeft() {
                TGDivider()
                HStack(spacing: 0) {
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
        target.gramsPerDay = isOnlyFood ? dog.dailyGrams : gramsPerDay
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
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
