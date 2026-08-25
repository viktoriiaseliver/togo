import SwiftUI
import SwiftData

/// Режим путешествия. Устроен как «Фокус»: включается на даты, меняет главный
/// экран и сам выключается. Не место, куда надо ходить.
struct TripSetupScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var trips: [Trip]

    @State private var destination = ""
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now
    @State private var transport: TransportKind = .car
    @State private var hours = 5.0
    @State private var lodging = ""

    var body: some View {
        TGScreen(title: "Едем с \(dog?.name ?? "собакой")") {
            TGExplainer(text: "Режим включится сам в день отъезда и выключится, когда вернётесь.")

            TGCard(spacing: 0) {
                LabeledField(label: "Куда") {
                    TextField("Ницца → Лион", text: $destination)
                }
                TGDivider()
                DatePicker("Когда", selection: $start, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                DatePicker("По", selection: $end, in: start..., displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                LabeledField(label: "Где живём") {
                    TextField("отель, с собакой можно", text: $lodging)
                }
            }

            TGCard {
                TGSectionHeader(title: "как", subtitle: "транспорт определяет окна натощак и остановки")
                TGChipGroup(
                    items: TransportKind.allCases,
                    title: \.title,
                    isSelected: { $0 == transport }
                ) { transport = $0 }
                if transport == .car {
                    Stepper(value: $hours, in: 1...20, step: 0.5) {
                        HStack {
                            Text("В дороге").textStyle(AppFont.body)
                            Spacer()
                            Text("\(hours, specifier: "%.1f") ч").textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGExplainer(text: transport.windowsExplainer)
            }

            if let dog { PackingListCard(dog: dog, days: dayCount) }
        } bottom: {
            TGButton(title: "Включить режим", systemImage: "car", isEnabled: !destination.isEmpty) { save() }
        }
        .navigationTitle("Поездка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dayCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func save() {
        guard let dog else { return }
        let trip = Trip(destination: destination, startDate: start, endDate: end, transport: transport)
        trip.travelHours = hours
        trip.lodging = lodging
        trip.dog = dog
        context.insert(trip)
        Haptics.success()
        dismiss()
    }
}

nonisolated extension TransportKind {
    var windowsExplainer: String {
        switch self {
        case .car: "Остановки каждые 2 часа: вода и пять минут походить. Приложение напомнит и запишет остановку одним тапом."
        case .plane: "Последняя еда за 4 часа, вода за час, долгий выход за 40 минут. В самолёте на пустой желудок спокойнее."
        case .train: "Выход на длинных стоянках, вода чаще обычного: в вагоне суше."
        }
    }

    /// Окна перед дорогой считаются от времени выезда.
    func windows(before departure: Date) -> [(String, Date, String)] {
        switch self {
        case .plane:
            [("−4 ч", departure.addingTimeInterval(-4 * 3600), "Последняя еда"),
             ("−1 ч", departure.addingTimeInterval(-3600), "Убрать воду"),
             ("−40 м", departure.addingTimeInterval(-40 * 60), "Долгий выход")]
        case .car:
            [("−2 ч", departure.addingTimeInterval(-2 * 3600), "Последняя еда"),
             ("−20 м", departure.addingTimeInterval(-20 * 60), "Выход перед машиной")]
        case .train:
            [("−2 ч", departure.addingTimeInterval(-2 * 3600), "Последняя еда"),
             ("−30 м", departure.addingTimeInterval(-30 * 60), "Выход перед посадкой")]
        }
    }
}

/// Сборы считаются из веса и порции — а не из общих таблиц.
struct PackingListCard: View {
    let dog: Dog
    let days: Int

    var body: some View {
        TGCard {
            TGSectionHeader(title: "что взять на \(Fmt.days(days))",
                            subtitle: "посчитано из веса \(Fmt.weight(dog.weightKg)) и порции \(dog.portionGrams) г")
            ForEach(items, id: \.0) { title, amount, note in
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    HStack {
                        Text(title).textStyle(AppFont.bodyEmphasis)
                        Spacer()
                        Text(amount).textStyle(AppFont.numeric(17))
                    }
                    Text(note).textStyle(AppFont.caption)
                }
                .frame(minHeight: 48)
            }
            TGExplainer(text: "Корм отсыпать в зип-пакеты по дням и подписать. Один пакет — в ручную кладь: если чемодан уедет не туда, у собаки останется ужин.")
            TGDivider()
            Text("Числа посчитаны из его данных, не из общих таблиц. Дозировки и всё медицинское сверь с врачом — приложение только считает и напоминает.")
                .textStyle(AppFont.caption)
        }
    }

    /// Запас — два кормления сверх поездки, вода в жару в полтора раза больше.
    private var items: [(String, String, String)] {
        let food = dog.dailyGrams * days + dog.portionGrams * 2
        let water = Double(dog.waterNormMl * days) * 1.5 / 1000
        return [
            ("Корм", "\(food) г", "\(dog.dailyGrams * days) г на дни плюс запас на два кормления"),
            ("Вода в дорогу", String(format: "%.1f л", water), "его норма ≈ \(dog.waterNormMl) мл в день, в жару больше · складная поилка"),
            ("Пакеты", "\(days * 4) шт", "по четыре на день, с запасом"),
        ]
    }
}

/// Блок дороги на главном. В поездке он встаёт между окном натощак и таймлайном.
struct TripTodayBlock: View {
    let trip: Trip
    let dog: Dog?
    let now: Date

    var body: some View {
        TGCard {
            HStack {
                Image(systemName: trip.transport.symbol)
                    .font(.system(size: Token.Size.iconMd, weight: .medium))
                    .foregroundStyle(Token.Action.primary)
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(trip.destination).textStyle(AppFont.cardTitle)
                    Text("день \(trip.dayNumber(on: now)) из \(trip.dayCount)").textStyle(AppFont.caption)
                }
                Spacer(minLength: 0)
            }
            TGDivider()
            if trip.dayNumber(on: now) <= 1 {
                departureWindows
            } else {
                onSiteAdvice
            }
        }
    }

    private var departureWindows: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: "до выезда")
            let departure = Calendar.current.startOfDay(for: trip.startDate)
                .addingTimeInterval(Double(trip.departureMinuteOfDay) * 60)
            ForEach(trip.transport.windows(before: departure), id: \.0) { offset, at, title in
                HStack(spacing: Token.Space.s12) {
                    Text(offset).textStyle(AppFont.numeric(13, weight: .medium)).frame(width: 44, alignment: .leading)
                    Text(title).textStyle(AppFont.body)
                    Spacer(minLength: 0)
                    Text(Fmt.clock(at)).textStyle(AppFont.caption)
                }
                .frame(minHeight: 38)
            }
            TGExplainer(text: "Окна натощак перед перелётом — общая практика, а не назначение. Если собака на терапии, приложение сведёт их с приёмами и покажет, где конфликт.")
        }
    }

    private var onSiteAdvice: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: "в незнакомом городе")
            Text("Три места, а не карта с сотней точек: нужен один ответ на вопрос «куда сейчас».")
                .textStyle(AppFont.caption)
            if let dog {
                Text("Норма воды ≈ \(dog.waterNormMl) мл в день. В жару смотри на эту строку первым делом: смена воды и корма чаще всего даёт сбой именно тут.")
                    .textStyle(AppFont.caption)
            }
        }
    }
}
