import SwiftUI
import SwiftData

/// Профиль собаки: питание, вес, уход, дрессировка.
/// Груминг и вес живут здесь и всплывают на главном только когда подошёл срок.
struct ProfileScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            if !canEdit {
                TGBanner(tone: .waiting, title: "Только чтение",
                         subtitle: "Профиль, питание и уход меняет тот, кому владелец выдал это право.",
                         systemImage: "lock")
            }
            if let dog {
                age(dog)
                nutrition(dog)
                weight(dog)
                marker(dog)
                treatment(dog)
            }
        }
        .disabled(false)
        .navigationTitle(dog?.name ?? "Профиль")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Что нельзя

    /// В профиле осталось только то, что про саму собаку.
    ///
    /// Здесь были и марка корма, и ссылка на режим — притом что до питания
    /// из этой же вкладки ведёт отдельный пункт. Получалось два пути к одному
    /// экрану, из которых один длиннее, и третье место, где заводят корм.
    /// Аллергии — единственное про еду, что действительно свойство собаки,
    /// а не расписания: их спрашивают у врача один раз и на всю жизнь.
    private func nutrition(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "чего нельзя")
            LabeledField(label: "Нельзя") {
                TextField("курица, кукуруза", text: Binding(
                    get: { dog.forbiddenFoods.joined(separator: ", ") },
                    set: { dog.forbiddenFoods = splitList($0) }
                ))
            }
            TGExplainer(text: "Попадёт в карточку для передержки и в напоминание перед поездкой. Сколько и во сколько собака ест — на экране «Питание».")
        }
        .disabled(!canEdit)
    }

    // MARK: Вес

    private func age(_ dog: Dog) -> some View {
        Group {
            if let description = dog.ageDescription, let stage = dog.lifeStage {
                TGCard {
                    HStack {
                        VStack(alignment: .leading, spacing: Token.Space.s2) {
                            Text("Возраст").textStyle(AppFont.cardTitle)
                            Text(stage.title).textStyle(AppFont.caption)
                        }
                        Spacer()
                        Text(description).textStyle(AppFont.numeric(20))
                    }
                    if stage == .puppy {
                        TGExplainer(text: "Щенку нужно больше кормлений в день и меньше нагрузки за раз. Число кормлений задаётся в «Режиме».")
                    } else if stage == .senior {
                        TGExplainer(text: "У пожилой собаки чаще меняются и вес, и режим выходов. Взвешивание раз в две недели тут полезнее, чем раз в месяц.")
                    }
                }
            }
        }
    }

    private func weight(_ dog: Dog) -> some View {
        NavigationLink { WeightScreen(dog: dog) } label: {
            TGCard {
                HStack {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Вес").textStyle(AppFont.cardTitle)
                        Text(dog.isWeightInRange ? "в коридоре, который назвал врач" : "вне коридора")
                            .textStyle(AppFont.caption)
                    }
                    Spacer()
                    Text(Fmt.weight(dog.weightKg)).textStyle(AppFont.numeric(22))
                    Image(systemName: "chevron.right")
                        .font(.system(size: Token.Size.iconSm, weight: .semibold))
                        .foregroundStyle(Token.Ink.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Чем маркируешь и чем платим

    private func marker(_ dog: Dog) -> some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "занятия")
            HStack {
                Text("Маркер").textStyle(AppFont.body)
                Spacer(minLength: Token.Space.s8)
                Picker("Маркер", selection: Binding(get: { dog.markerKind }, set: { dog.markerKind = $0 })) {
                    ForEach(MarkerKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Token.Ink.secondary)
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            LabeledField(label: "Чем платим") {
                TextField("сыр, индейка, мячик", text: Binding(
                    get: { dog.rewards.joined(separator: ", ") },
                    set: { dog.rewards = splitList($0) }
                ))
            }
            TGDivider()
            Toggle(isOn: Binding(get: { dog.trainingFoodFromPortion }, set: { dog.trainingFoodFromPortion = $0 })) {
                Text("Корм на занятия — из порции").textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGDivider()
            Stepper(value: Binding(get: { dog.sessionLengthMinutes }, set: { dog.sessionLengthMinutes = $0 }), in: 2...5) {
                HStack {
                    Text("Длина занятия").textStyle(AppFont.body)
                    Spacer()
                    Text("\(dog.sessionLengthMinutes) мин").textStyle(AppFont.numeric(15))
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            TGExplainer(text: "Ограничения на лакомства нет. Есть дневная норма, часть которой собака зарабатывает, — это и снимает конфликт между занятиями и весом.")
        }
        .disabled(!canEdit)
    }

    // MARK: Лечение

    private func treatment(_ dog: Dog) -> some View {
        TGCard {
            Toggle(isOn: Binding(get: { dog.isOnTreatment }, set: { dog.isOnTreatment = $0 })) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Собака на лечении").textStyle(AppFont.body)
                    Text("даёт вкладку «Здоровье», дозы, окно натощак и отчёты").textStyle(AppFont.caption)
                }
            }
            TGExplainer(text: "Выключишь — вкладка исчезнет, а записи останутся в истории.")
        }
        .disabled(!canEdit)
    }


    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
