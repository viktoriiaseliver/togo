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
            CinemaHeader("Если что-то случилось", надпись: "одно касание", отступы: false)
            disclaimer
            contactsCard
            toxicCard
            vetBriefCard
        }
        .navigationTitle("Если что-то случилось")
        .cinemaScreen(экран: .sub("emergency"))
        .usageScreen(.emergency)
    }

    // MARK: Главное

    private var disclaimer: some View {
        TGBanner(
            tone: .alarm,
            title: "Решает врач, не приложение",
            subtitle: "Togo не ставит диагнозов и не лечит. Здесь только телефоны и данные, которые трудно вспомнить, когда страшно.",
            systemImage: "cross.case"
        )
    }

    // MARK: Телефоны

    private var contactsCard: some View {
        TGCard {
            TGSectionHeader(title: "позвонить")
            if contacts.isEmpty {
                // **Подсказка посылала не туда** (аудит 29.10.2026):
                // «впиши их в профиле собаки», а в профиле телефонов нет —
                // они на экране «Документы и контакты», и дороги отсюда
                // туда не было вовсе. Человек в панике искал бы поле,
                // которого нет. Теперь дорога — строкой здесь же.
                TGExplainer(text: "Телефонов пока нет. Впиши их по строке ниже — тогда в нужный момент не придётся их искать.")
                if let dog {
                    TGLink(title: "Документы и контакты", systemImage: "doc.text.image") {
                        DocumentsScreen(dog: dog)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(contacts, id: \.0) { title, name, phone in
                    Button { call(phone) } label: {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: Token.Size.iconMd, weight: .semibold))
                                .foregroundStyle(Token.Action.doneText)
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

    /// Телефон без имени — всё равно телефон.
    ///
    /// **До 29.10.2026 имя было условием показа**: вписал номер клиники,
    /// а название не вписал — и экран говорил «телефонов пока нет»,
    /// то есть прятал единственное, ради чего он открыт. Имени нет —
    /// строка называется тем, кто это: «Ветеринар», «Клиника 24 ч»
    /// (подписи полей на экране документов, те же ключи).
    ///
    /// Роль — через каталог: `String`-значение, вставленное в `Text`,
    /// мимо перевода рисуется дословно, и француз видел «клиника».
    private var contacts: [(String, String, String)] {
        var result: [(String, String, String)] = []
        if let phone = dog?.vetPhone.flatMap(Fmt.notBlank) {
            result.append((String(localized: "ветеринар"),
                           dog?.vetName.flatMap(Fmt.notBlank) ?? String(localized: "Ветеринар"),
                           phone))
        }
        if let phone = dog?.clinicPhone.flatMap(Fmt.notBlank) {
            result.append((String(localized: "клиника"),
                           dog?.clinicName.flatMap(Fmt.notBlank) ?? String(localized: "Клиника 24 ч"),
                           phone))
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
            // Без рода — ни собаки, ни человека (29.10.2026): «съела»
            // у кобеля и «сама» у мужчины. Заголовок тот же, что пункт
            // плашки на вкладке собаки, — одно место называется одинаково.
            TGSectionHeader(title: "что нельзя есть",
                            subtitle: "не вызывай рвоту без врача — при части веществ это делает хуже")
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
                                .wraps()
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
            // «что скажут спросить» читалось как обрывок фразы; имя
            // раздела — то, которым его зовёт плашка на вкладке собаки.
            TGSectionHeader(title: "справка врачу",
                            subtitle: "врач спросит это первым — тут всё уже собрано")
            ForEach(brief, id: \.0) { title, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(title).textStyle(AppFont.caption)
                    Spacer(minLength: Token.Space.s12)
                    Text(value)
                        .textStyle(AppFont.bodyEmphasis)
                        .multilineTextAlignment(.trailing)
                        .wraps()
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
            ("Кличка", dog.displayName),
            ("Вес", Fmt.weight(dog.weightKg)),
        ]
        if let breed = dog.breed { rows.append(("Порода", breed)) }
        if let age = dog.ageDescription { rows.append(("Возраст", age)) }
        if let chip = dog.chipNumber, !chip.isEmpty { rows.append(("Чип", chip)) }

        let active = dog.medications.filter { !$0.isPaused }
        if !active.isEmpty {
            rows.append(("Принимает", active.map { "\($0.name) \($0.doseText)" }.joined(separator: ", ")))
        }
        // «Ел последний раз» → «Последняя еда»: мужской род у суки,
        // а ключ без рода уже лежал переведённым (окна поездки).
        //
        // И день, когда это было не сегодня: одно «08:40» врач читает
        // как «утром», а запись могла быть позавчерашней — тот, кто
        // в панике не отметил еду, получал ложную справку.
        if let lastMeal = Diary.last(dog.events, kind: .meal) {
            rows.append((String(localized: "Последняя еда"), когда(lastMeal.date)))
        }
        if let lastStool = Diary.last(dog.events, kind: .stool) {
            rows.append(("Стул", когда(lastStool.date)))
        }
        return rows
    }

    private func когда(_ дата: Date) -> String {
        Calendar.current.isDateInToday(дата)
            ? Fmt.clock(дата)
            : Fmt.shortDay(дата) + ", " + Fmt.clock(дата)
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

    /// # На этом экране ДВА права, и это не оплошность
    ///
    /// `editProfile` закрывает три карточки ниже — номера, телефоны
    /// и приметы. Это **опознание и контакты, а не медицина**: номер
    /// чипа и паспорта нужен, чтобы вернуть потерявшуюся собаку,
    /// телефон ветеринара — чтобы позвонить, приметы — чтобы собрать
    /// объявление. Выгульщику без `seeMedical` всё это нужно,
    /// и отнимать у него телефон клиники было бы вредно.
    ///
    /// Карточка снимков (`DocumentPhotosCard`) закрыта **своими**
    /// правами — `seeMedical` на показ, `editTreatment` на правку, —
    /// потому что в ней лежит ветпаспорт с прививками, анализы
    /// и назначения. Разбор и таблица по пяти ролям — там же.
    ///
    /// **Проверено 26.10.2026, что одним правом здесь не обойтись:**
    /// поставь на весь экран `seeMedical` — и помощник потеряет
    /// телефон клиники; оставь на весь экран `editProfile` — и он же
    /// листает анализы, как было до этой правки.
    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            // Имя экрана — то, которым его зовут обе двери (строка
            // вкладки собаки и «Если что-то случилось»): половина экрана —
            // телефоны, и «Документы» обещали только бумаги. 29.10.2026.
            CinemaHeader("Документы и контакты", надпись: "когда спросят", отступы: false)
            // Плашка на ТРИ выключенных карточки: номера, телефоны
            // и приметы. Экран, на котором всё поле ввода мертво
            // и ни слова о причине, — худший вид этого дефекта:
            // человек решит, что приложение сломалось.
            //
            // Снимки о себе говорят сами и своим правом — иначе
            // одна плашка отвечала бы за два разных отказа и назвала
            // бы человеку не то право, которое надо просить.
            if !canEdit { ПлашкаПрава(право: .editProfile) }
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
                LabeledField(label: "Телефон", spokenLabel: "Телефон ветеринара") {
                    // `+…`, а не `+33…`.
                    //
                    // Код страны в подсказке — не формат, а **предположение
                    // о том, где человек живёт**. Украиноязычный в Ницце
                    // набирает `+33`, француз в Киеве `+380`, и угадать
                    // это нельзя: номер принадлежит стране, где ВЕТЕРИНАР,
                    // а не где настроен телефон. Регион устройства был бы
                    // догадкой получше, но всё равно догадкой.
                    //
                    // Формат — «начинается с плюса», и `+…` говорит ровно
                    // его, не соврав никому.
                    TextField("+…", text: binding(\.vetPhone)).keyboardType(.phonePad)
                }
                TGDivider()
                LabeledField(label: "Клиника 24 ч") {
                    TextField("название", text: binding(\.clinicName))
                }
                TGDivider()
                LabeledField(label: "Телефон", spokenLabel: "Телефон клиники") {
                    TextField("+…", text: binding(\.clinicPhone)).keyboardType(.phonePad)
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
                    TGExplainer(text: "Своего телефона приложение не знает — допиши его в объявление перед отправкой. Номер ветеринара сюда не ставится: звонить должны тебе.")
                }
            }

            DocumentPhotosCard(dog: dog)

            TGExplainer(text: "Всё это лежит на телефоне и никуда не отправляется само.")
        }
        .navigationTitle("Документы и контакты")
        .cinemaScreen(экран: .sub("docs"))
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Dog, String?>) -> Binding<String> {
        Binding(
            get: { dog[keyPath: keyPath] ?? "" },
            set: { dog[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var lostText: String? {
        // ДВА КЛЮЧА, А НЕ ПРОЧЕРК В ОДНОМ (замер 25.10.2026).
        //
        // `Fmt.weight(0)` печатал «0,0 г», и плакат уходил чужим людям
        // с ложным весом; прочерк на его месте — «Потерялась собака:
        // Стич, метис, —» — читается как обрыв, а не как «не записано».
        // Этот текст человек отправляет незнакомым, и читают его один
        // раз, без права переспросить.
        //
        // Трёхместный ключ остаётся живым: когда вес записан, едет он.
        var parts = [Fmt.weightIfKnown(dog.weightKg).map {
            String(localized: "Потерялась собака: \(dog.displayName), \(dog.breed ?? String(localized: "метис")), \($0)")
        } ?? String(localized: "Потерялась собака: \(dog.displayName), \(dog.breed ?? String(localized: "метис"))")]
        if let age = dog.ageDescription { parts.append(String(localized: "Возраст: \(age)")) }
        if let chip = dog.chipNumber, !chip.isEmpty { parts.append(String(localized: "Чип: \(chip)")) }
        if let marks = dog.distinctiveMarks, !marks.isEmpty { parts.append(String(localized: "Приметы: \(marks)")) }
        // # Телефона ветеринара на плакате НЕТ, и это починка (29.10.2026)
        //
        // Здесь стояло `Ветеринар: <vetPhone>` — единственный номер
        // объявления. Нашедший собаку звонил бы врачу, а не хозяину:
        // врач собаку не ищет, на звонок незнакомца в выходной
        // не ответит, а владельца по номеру чипа найдёт не сразу.
        //
        // Своего телефона у владельца в модели нет — ни у `Dog`,
        // ни у `FamilyMember` (поля схемы без спроса не заводим).
        // Поэтому номер в текст не подставляется вовсе, а под кнопкой
        // сказано дописать свой перед отправкой. Пустое место честнее
        // чужого номера: его видно и его заполнят.
        return parts.count > 1 ? parts.joined(separator: "\n") : nil
    }
}
