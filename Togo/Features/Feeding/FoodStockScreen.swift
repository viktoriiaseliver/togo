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
                Text(stock.summary)
                    .textStyle(AppFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Token.Space.s8)
            VStack(alignment: .trailing, spacing: Token.Space.s2) {
                Text(stock.daysLeft.map { Fmt.days($0) } ?? "—")
                    .textStyle(AppFont.numeric(15).color(
                        stock.needsRestock ? Token.Status.waitingText : Token.Ink.primary
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
                    message: "Добавь то, чем кормишь. Сухой считается мешками, влажный — банками; если даёшь и то и другое, добавь оба и укажи, сколько граммов в день приходится на каждый.",
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
        .navigationTitle("Запас корма")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isAdding) { FoodStockEditorSheet(dog: dog) }
        .sheet(item: $editing) { stock in FoodStockEditorSheet(stock: stock, dog: dog) }
    }

    /// Сходится ли сумма по кормам с дневной нормой. Не ошибка — но человек
    /// должен видеть расхождение, а не узнавать о нём через месяц по весам.
    private var balanceCard: some View {
        TGCard {
            HStack {
                Text("Выходит в день").textStyle(AppFont.body)
                Spacer()
                Text("\(total) г").textStyle(AppFont.numeric(20))
            }
            if dog.dailyGrams > 0, total != dog.dailyGrams {
                TGBanner(
                    tone: .waiting,
                    title: total > dog.dailyGrams ? "Больше нормы из профиля" : "Меньше нормы из профиля",
                    subtitle: "В профиле стоит \(dog.dailyGrams) г в день, по кормам выходит \(total) г. Это не ошибка — но стоит проверить, что вы имели в виду.",
                    systemImage: "arrow.left.arrow.right"
                )
            }
            if dog.stocks.contains(where: { $0.kind == .wet }) {
                TGExplainer(text: FoodKind.wet.caution ?? "")
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
                            packs == 0 ? Token.Action.done : Token.Ink.primary
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

    private var existingGramsPerDay: Int {
        allStocks
            .filter { $0.dog?.persistentModelID == dog.persistentModelID }
            .map(\.gramsPerDay)
            .reduce(0, +)
    }

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
                closeTitle: isNew ? "Отмена" : "Закрыть") {
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
            Stepper(value: $gramsPerDay, in: 0...2000, step: kind == .wet ? 25 : 5) {
                HStack {
                    Text("В день").textStyle(AppFont.body)
                    Spacer()
                    Text("\(gramsPerDay) г").textStyle(AppFont.numeric(17))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)

            if kind == .wet, gramsPerDay > 0, packGrams > 0 {
                TGDivider()
                HStack {
                    Text("Это примерно").textStyle(AppFont.body)
                    Spacer()
                    Text(String(format: "%.1f %@ в день",
                                Double(gramsPerDay) / Double(packGrams),
                                kind.unitName(count: 1)))
                        .textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                }
                .frame(minHeight: Token.Size.tapTarget)
            }

            let preview = FoodStock(kind: kind, packGrams: packGrams,
                                    packsLeft: packsLeft, gramsPerDay: gramsPerDay)
            if let days = preview.daysLeft {
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
            gramsPerDay = existingGramsPerDay == 0
                ? dog.dailyGrams
                : max(0, dog.dailyGrams - existingGramsPerDay)
        }
        loaded = true
    }

    private func save() {
        let target = stock ?? FoodStock(kind: kind, brand: brand, packGrams: packGrams,
                                        packsLeft: packsLeft, gramsPerDay: gramsPerDay)
        target.kind = kind
        target.brand = brand
        target.packGrams = packGrams
        target.packsLeft = packsLeft
        target.gramsPerDay = gramsPerDay
        if stock == nil {
            target.openedAt = Date()
            target.dog = dog
            context.insert(target)
        }
        // Сохраняем сразу: иначе связь применяется не мгновенно,
        // и человек возвращается на экран, где ничего не изменилось.
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
