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
                правкаИУдаление(dog)
            }
        }
        .disabled(false)
        .navigationTitle(заголовок)
        .posterHeader(.значение(dog.flatMap(\.nameIfAny) ?? String(localized: "Профиль")))
        .navigationBarTitleDisplayMode(.large)
    }

    /// Заголовок экрана.
    ///
    /// **Было `dog?.name ?? "Профиль"`, и откат не срабатывал.** `??`
    /// отвечает на `nil`, а кличка — непустая строка по типу: у собаки
    /// без клички она `""`, и человек получал экран **без заголовка
    /// вовсе**. Та же причина, что у пустых собак в списке (отзыв
    /// 06.10.2026): откат написан на отсутствие, а приходит пустота.
    ///
    /// `Text` здесь не для красоты: `navigationTitle` со значением типа
    /// `String` берёт нелокализующую перегрузку, и «Профиль» рисовалось
    /// по-русски на французском экране. `Text("Профиль")` с литералом
    /// идёт через каталог.
    ///
    /// Годность клички решает единственная точка показа —
    /// `Dog.nameIfAny`, — а не местная проверка: первая редакция
    /// этой правки звала `DogPayload.hasUsableName` прямо здесь, и это
    /// была бы двадцать вторая копия правила на двадцать второй
    /// поверхности.
    ///
    /// `nil` здесь значит «собаки нет вовсе», и тогда заголовок свой —
    /// «Профиль», а не запасная кличка: экран без собаки это не собака
    /// без клички.
    private var заголовок: Text {
        guard let имя = dog.flatMap(\.nameIfAny) else { return Text("Профиль") }
        return Text(имя)
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
                        // **Вторая поверхность той же лжи, и здесь она
                        // была сильнее.** Наряд назвал `HealthScreen`;
                        // эта строка нашлась замером мест вызова
                        // предиката и врала хуже: при отсутствующем
                        // коридоре она говорила «в коридоре, который
                        // назвал ВРАЧ» — то есть приписывала
                        // утверждение врачу, который ничего не называл.
                        //
                        // > Починка на одной поверхности из двух
                        // > выглядит законченной. Предикат
                        // > `isWeightInRange` зовут РОВНО два показа,
                        // > и оба сваливали «коридора нет» в ветку
                        // > «всё хорошо».
                        //
                        // Молчим при `.normUnknown` по той же причине,
                        // что на «Здоровье»: нового слова под заморозкой
                        // текстов не заводим, а ложного не говорим.
                        switch dog.weightVerdict {
                        case .withinRange:
                            Text("в коридоре, который назвал врач")
                                .textStyle(AppFont.caption)
                        case .below, .above:
                            Text("вне коридора")
                                .textStyle(AppFont.caption)
                        case .normUnknown, .indeterminate:
                            EmptyView()
                        }
                    }
                    Spacer()
                    Text(Fmt.weight(dog.weightKg)).textStyle(AppFont.numeric(22))
                    Image(systemName: "chevron.right")
                        .font(.system(size: Token.Size.iconSm, weight: .semibold))
                        .foregroundStyle(Token.Ink.secondary)
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
            // Тумблер не просто пишет флаг: включение возвращает
            // отменённые препараты, выключение закрывает курс так же,
            // как кнопка «Курс завершён». Иначе схема оживала наполовину —
            // вкладка есть, а все препараты в ней отменены.
            Toggle(isOn: Binding(
                get: { dog.isOnTreatment },
                set: { isOn in
                    if isOn {
                        TreatmentCourse.resume(dog, context: context)
                    } else {
                        TreatmentCourse.finish(dog, by: appState.currentUserName, context: context)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text("Собака на лечении").textStyle(AppFont.body)
                    Text("включает дозы по часам, окно натощак и напоминания").textStyle(AppFont.caption)
                }
            }
            TGExplainer(text: "Выключишь — курс закроется, а записи останутся в истории.")
        }
        .disabled(!canEdit)
    }


    /// Дорога к правке и удалению — **внизу профиля, как и обещано**.
    ///
    /// `SettingsScreen` в подвале списка собак говорит человеку: «Удалить
    /// собаку можно в её профиле, внизу». Замер `togo-02` 07.10.2026:
    /// `grep 'DogEditorScreen(dog'` даёт **ноль** во всём дереве. Оба
    /// вызова — `DogEditorScreen()` без собаки, то есть `isNew` всегда
    /// `true`, и блок с кнопкой «Удалить собаку» вместе с подтверждением
    /// и объяснением про каскад **не рисовался никогда**.
    ///
    /// То есть кнопка была написана правильно и недостижима: наш класс
    /// «имя упомянуто, и от упоминания ничего не происходит» — и в самом
    /// дорогом месте, потому что здесь упоминание было обещанием
    /// человеку.
    ///
    /// **Почему дорога заведена здесь, а не в строке списка.** Выбор был
    /// из двух: либо строка «Настройки → собаки» ведёт сразу
    /// в `DogEditorScreen(dog:)`, либо дорога появляется там, куда
    /// указывает текст. Второе: текст называет место («в её профиле,
    /// внизу»), и правка, совпадающая с обещанием, не требует править
    /// обещание — а третьего у нас нет, обещание либо становится
    /// правдой, либо меняется. Первое заодно сменило бы поведение
    /// нажатия на собаку: сейчас оно открывает профиль, а не редактор.
    ///
    /// Пока этой дороги не было, уборка безымянных записей при запуске
    /// оказывалась **единственным** выходом, то есть протезом вместо
    /// починки. Теперь человек убирает своё сам, а уборка остаётся тем,
    /// чем должна быть.
    @ViewBuilder
    private func правкаИУдаление(_ dog: Dog) -> some View {
        if canEdit {
            TGCard {
                NavigationLink {
                    DogEditorScreen(dog: dog)
                } label: {
                    LabeledContent("Править и удалить", value: "")
                }
            }
        }
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
