import SwiftUI
import SwiftData

/// «Если что-то случилось».
///
/// Экран для одной ситуации: собаке плохо, и надо действовать, а не читать.
/// Поэтому сверху — телефоны в один тап, потом то, что она могла съесть,
/// и только потом справка для врача. Приложение здесь ничего не решает
/// и не лечит: оно помнит номера и данные, которые в панике не вспомнить.
struct EmergencyScreen: View {
    let dog: Dog?

    @Environment(\.openURL) private var openURL
    @State private var expanded: String?

    var body: some View {
        TGScreen {
            disclaimer
            contactsCard
            toxicCard
            vetBriefCard
        }
        .navigationTitle("Если что-то случилось")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Главное

    private var disclaimer: some View {
        TGBanner(
            tone: .alarm,
            title: "Решает врач, не приложение",
            subtitle: "Того не ставит диагнозов и не лечит. Здесь только телефоны и данные, которые трудно вспомнить, когда страшно.",
            systemImage: "cross.case"
        )
    }

    // MARK: Телефоны

    private var contactsCard: some View {
        TGCard {
            TGSectionHeader(title: "позвонить")
            if contacts.isEmpty {
                TGExplainer(text: "Телефонов пока нет. Впиши их в профиле собаки — тогда в нужный момент не придётся их искать.")
            } else {
                ForEach(contacts, id: \.0) { title, name, phone in
                    Button { call(phone) } label: {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: Token.Size.iconMd, weight: .semibold))
                                .foregroundStyle(Token.Action.done)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(name).textStyle(AppFont.bodyEmphasis)
                                Text("\(title) · \(phone)").textStyle(AppFont.caption)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Позвонить: \(name)")
                }
            }
        }
    }

    private var contacts: [(String, String, String)] {
        var result: [(String, String, String)] = []
        if let name = dog?.vetName, let phone = dog?.vetPhone, !phone.isEmpty {
            result.append(("ветеринар", name, phone))
        }
        if let name = dog?.clinicName, let phone = dog?.clinicPhone, !phone.isEmpty {
            result.append(("клиника", name, phone))
        }
        return result
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }

    // MARK: Съела что-то не то

    private var toxicCard: some View {
        TGCard {
            TGSectionHeader(title: "съела что-то не то",
                            subtitle: "не вызывай рвоту сама — при части веществ это делает хуже")
            ForEach(ToxicItem.common) { item in
                Button {
                    withAnimation(.easeInOut(duration: Token.Duration.instant)) {
                        expanded = expanded == item.id ? nil : item.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Token.Space.s4) {
                        HStack(spacing: Token.Space.s8) {
                            Circle()
                                .fill(item.urgency == .callNow ? Token.Status.overdueText : Token.Status.waitingText)
                                .frame(width: 8, height: 8)
                            Text(item.name).textStyle(AppFont.bodyEmphasis)
                            Spacer(minLength: Token.Space.s8)
                            Text(item.urgency == .callNow ? "сейчас" : "наблюдать")
                                .textStyle(AppFont.micro.color(
                                    item.urgency == .callNow ? Token.Status.overdueText : Token.Status.waitingText
                                ))
                        }
                        if expanded == item.id {
                            Text(item.detail)
                                .textStyle(AppFont.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.urgency.title)
                                .textStyle(AppFont.captionEmphasis.color(Token.Ink.primary))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Token.Size.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item.id != ToxicItem.common.last?.id { TGDivider() }
            }
            TGExplainer(text: "Список короткий намеренно: длинный никто не дочитает. Если её нет здесь, но собаке плохо — всё равно звони.")
        }
    }

    // MARK: Что сказать врачу

    private var vetBriefCard: some View {
        TGCard {
            TGSectionHeader(title: "что скажут спросить",
                            subtitle: "врач спросит это первым — тут всё уже собрано")
            ForEach(brief, id: \.0) { title, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(title).textStyle(AppFont.caption)
                    Spacer(minLength: Token.Space.s12)
                    Text(value)
                        .textStyle(AppFont.bodyEmphasis)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 38)
            }
            if let text = briefText {
                ShareLink(item: text) {
                    TGListRow(title: "Отправить это в мессенджер",
                              systemImage: "square.and.arrow.up", accessory: .none)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var brief: [(String, String)] {
        guard let dog else { return [] }
        var rows: [(String, String)] = [
            ("Кличка", dog.name),
            ("Вес", Fmt.weight(dog.weightKg)),
        ]
        if let breed = dog.breed { rows.append(("Порода", breed)) }
        if let age = dog.ageDescription { rows.append(("Возраст", age)) }
        if let chip = dog.chipNumber, !chip.isEmpty { rows.append(("Чип", chip)) }

        let active = dog.medications.filter { !$0.isPaused }
        if !active.isEmpty {
            rows.append(("Принимает", active.map { "\($0.name) \($0.doseText)" }.joined(separator: ", ")))
        }
        if let lastMeal = Diary.last(dog.events, kind: .meal) {
            rows.append(("Ел последний раз", Fmt.clock(lastMeal.date)))
        }
        if let lastStool = Diary.last(dog.events, kind: .stool) {
            rows.append(("Стул", Fmt.clock(lastStool.date)))
        }
        return rows
    }

    private var briefText: String? {
        guard !brief.isEmpty else { return nil }
        return brief.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }
}

/// Документы: чип, паспорт, страховка и фотографии.
/// Нужны в двух случаях — у врача и когда собака потерялась.
struct DocumentsScreen: View {
    let dog: Dog

    @Environment(AppState.self) private var appState

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "номера")
                LabeledField(label: "Чип") {
                    TextField("не указан", text: binding(\.chipNumber))
                        .keyboardType(.numbersAndPunctuation)
                }
                TGDivider()
                LabeledField(label: "Паспорт") {
                    TextField("не указан", text: binding(\.passportNumber))
                }
                TGDivider()
                LabeledField(label: "Страховка") {
                    TextField("не указана", text: binding(\.insuranceNumber))
                }
            }
            .disabled(!canEdit)

            TGCard(spacing: 0) {
                TGSectionHeader(title: "кому звонить",
                                subtitle: "эти телефоны появятся на экране «Если что-то случилось»")
                LabeledField(label: "Ветеринар") {
                    TextField("имя", text: binding(\.vetName))
                }
                TGDivider()
                LabeledField(label: "Телефон") {
                    TextField("+33…", text: binding(\.vetPhone)).keyboardType(.phonePad)
                }
                TGDivider()
                LabeledField(label: "Клиника 24 ч") {
                    TextField("название", text: binding(\.clinicName))
                }
                TGDivider()
                LabeledField(label: "Телефон") {
                    TextField("+33…", text: binding(\.clinicPhone)).keyboardType(.phonePad)
                }
            }
            .disabled(!canEdit)

            TGCard {
                TGSectionHeader(title: "если потерялась",
                                subtitle: "приметы для объявления — писать их в панике невозможно")
                TextEditor(text: binding(\.distinctiveMarks))
                    .textStyle(AppFont.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .disabled(!canEdit)
                if let text = lostText {
                    ShareLink(item: text) {
                        TGListRow(title: "Собрать объявление",
                                  systemImage: "square.and.arrow.up", accessory: .none)
                    }
                    .buttonStyle(.plain)
                }
            }

            TGExplainer(text: "Всё это лежит на телефоне и никуда не отправляется само. Фотографии паспорта удобно держать здесь же — на границе и у врача их спрашивают первыми.")
        }
        .navigationTitle("Документы")
        .navigationBarTitleDisplayMode(.large)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Dog, String?>) -> Binding<String> {
        Binding(
            get: { dog[keyPath: keyPath] ?? "" },
            set: { dog[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var lostText: String? {
        var parts = ["Потерялась собака: \(dog.name), \(dog.breed ?? "метис"), \(Fmt.weight(dog.weightKg))"]
        if let age = dog.ageDescription { parts.append("Возраст: \(age)") }
        if let chip = dog.chipNumber, !chip.isEmpty { parts.append("Чип: \(chip)") }
        if let marks = dog.distinctiveMarks, !marks.isEmpty { parts.append("Приметы: \(marks)") }
        if let phone = dog.vetPhone, !phone.isEmpty { parts.append("Ветеринар: \(phone)") }
        return parts.count > 1 ? parts.joined(separator: "\n") : nil
    }
}
