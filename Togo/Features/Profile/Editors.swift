import SwiftUI
import SwiftData

/// Собака: создать, поправить, удалить.
///
/// Один экран на все три действия — так человеку не надо гадать, где
/// заводится вторая собака и где убирается первая.
struct DogEditorScreen: View {
    /// nil — создаём новую.
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var draft = DogDraft()
    @State private var isConfirmingDelete = false
    @State private var loaded = false

    /// Фокус поля веса — единственного `.decimalPad` на экране.
    ///
    /// **Здесь это дороже, чем в онбординге.** Черновик тут локальный
    /// `@State`, сохранения по выходу нет, и до 15.10 единственным
    /// выходом с цифровой клавиатуры было «назад» — то есть выход
    /// **выбрасывал только что набранный вес**. В онбординге тот же
    /// жест введённое сохраняет.
    @FocusState private var весВФокусе: Bool

    /// Фокус поля клички. Отдельным свойством, а не общим
    /// перечислением: `весВФокусе` читает `.готовоНадКлавиатурой`,
    /// и менять его тип значило бы трогать выход с клавиатуры,
    /// у которого своя причина и свой разбор выше.
    @FocusState private var кличкаВФокусе: Bool

    /// «Готово» нажали при пустой кличке.
    ///
    /// Поле состояния, а не вычисление из пустоты: строка появляется
    /// **по нажатию**. Пустое поле свежей формы — это начало работы,
    /// а не ошибка человека.
    @State private var кличкаНеНазвана = false

    private var кличкаПуста: Bool {
        draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isNew: Bool { dog == nil }

    var body: some View {
        TGScreen {
            CinemaHeader(isNew ? "Новая собака" : "Профиль", отступы: false)
            // **Было «Обязательны только кличка и вес» — и это ЛОЖЬ
            // с двух сторон сразу.**
            //
            // Со стороны решения: вес необязателен (ОТВЕТЫ-круг-5,
            // п. 1 — «на шаге „собака" обязательна только кличка»).
            // Со стороны кода: `save()` (`:226`) пишет
            // `dog.weightKg = draft.weightValue ?? dog.weightKg`,
            // то есть пустой вес он переживает без единого слова.
            //
            // Обещание в шапке формы читают до ввода, а отказ кнопки —
            // после, и сходились они только случайно.
            TGExplainer(text: "Обязательна только кличка. Остальное можно пропустить и заполнить когда угодно.")

            TGCard(spacing: 0) {
                LabeledField(label: "Кличка") {
                    // **Подсказка — слово, а не кличка.** Второе место
                    // того же дефекта: в онбординге его закрыли 23.10
                    // (`OnboardingSteps.swift:190`), здесь он дожил
                    // до 25.10.
                    //
                    // `TextField(_ titleKey:)` принимает
                    // `LocalizedStringKey`, поэтому ЛЮБОЙ
                    // литерал-подсказка уезжает в каталог и переводится.
                    // Замер 25.10 по каталогу: ключ `Стич` имеет
                    // переводы `en: Stitch` и `fr: Stitch` — то есть
                    // у француза в поле клички стояло **Stitch**,
                    // а в демо-данных рядом **Стич**.
                    //
                    // Это живой отзыв `AEXYTDmy` от 23.09: «Где-то
                    // stitch а где то Стич». Починили одно место
                    // из двух, и отзыв остался живым ещё на месяц.
                    //
                    // > **Починка по адресу из отзыва закрывает адрес,
                    // > а не класс.** Искать надо было форму
                    // > `TextField("<слово>"`, а не слово «Стич».
                    TextField("Кличка", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($кличкаВФокусе)
                }
                // Отказ — ЗДЕСЬ, под своим полем, а не у кнопки:
                // человек смотрит туда, где надо исправлять
                // (ОТВЕТЫ-круг-5, п. 1). Ключ тот же, что у шага
                // онбординга, — два экрана об одном говорят одним
                // словом, и перевод у них один.
                if кличкаНеНазвана {
                    Text("Напиши кличку — так её будет звать дневник")
                        .textStyle(AppFont.micro.color(Token.Status.overdueText))
                        .wraps()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Token.Space.s8)
                        // Озвучке отказ приходит сменой текста,
                        // а не цветом: цвета она не читает вовсе.
                        .accessibilityAddTraits(.isStaticText)
                }
                TGDivider()
                LabeledField(label: "Вес") {
                    HStack(spacing: Token.Space.s4) {
                        // «4,1» — то же самое: подсказка про ФОРМАТ,
                        // а не пример веса. У числа перевода нет,
                        // но ключ в каталоге заводится всё равно
                        // и зря просит вычитки на четырёх языках.
                        TextField("Вес", text: $draft.weight).keyboardType(.decimalPad)
                            .focused($весВФокусе)
                        Text("кг").textStyle(AppFont.caption)
                    }
                }
                TGDivider()
                LabeledField(label: "Порода") {
                    TextField("можно пропустить", text: $draft.breed)
                }
                TGDivider()
                // **Пол спрашивали ровно в одном месте — в онбординге.**
                //
                // Замер 08.10.2026 по живой выгрузке: у всех шестнадцати
                // собак `sexRaw: unknown`, включая Стича. Поправить это
                // было нечем: во всём `Togo/` пол упомянут трижды —
                // дважды в онбординге и один раз комментарием.
                //
                // Дыра шире, чем «нельзя исправить»: этот экран заводит
                // вторую и следующих собак (`:128`, `draft.makeDog()`),
                // а пола в черновике задать было негде — значит собака,
                // заведённая НЕ через онбординг, получала `unknown`
                // навсегда. Само поле в `DogDraft` лежит с первого дня
                // (`OnboardingFlow.swift:158`), не хватало только строки.
                //
                // > `OnboardingSteps.swift:87` обещает: «искать его потом
                // > в профиле никто не будет» — и писалось это в уверенности,
                // > что в профиле пол есть. Его там не было ни строкой.
                HStack {
                    Text("Кто это").textStyle(AppFont.body)
                    Spacer(minLength: Token.Space.s8)
                    Picker("Кто это", selection: $draft.sex) {
                        ForEach(DogSex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Token.Ink.secondary)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if draft.sex != .unknown {
                    TGDivider()
                    Toggle(isOn: $draft.isNeutered) {
                        Text(draft.sex == .male ? "Кастрирован" : "Стерилизована")
                            .textStyle(AppFont.body)
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }

            TGCard {
                Toggle(isOn: $draft.isOnTreatment) {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Собака на лечении").textStyle(AppFont.body)
                        Text("включит вкладку «Здоровье», дозы и окно натощак").textStyle(AppFont.caption)
                    }
                }
            }

            if !isNew {
                TGCard {
                    TGSectionHeader(title: "убрать")
                    TGButton(title: "Удалить собаку", variant: .destructive, size: .medium, systemImage: "trash") {
                        isConfirmingDelete = true
                    }
                    TGExplainer(text: "Вместе с ней исчезнет весь её дневник — одиннадцать видов записей: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки и запас корма. Выгрузить дневник можно в «Настройки → Данные и приватность».")
                }
            }
        }
        // **Низ отдан системе, а не слоту `TGScreen`.** Второй адрес
        // этой правки; первый — `DogStep` (`d7e275b`), и там же разбор
        // механизма: слот каркаса считает запас от высоты САМОЙ панели
        // (`TGScaffolds.swift:177`), а клавиатура панель поднимает
        // и высоту её не меняет — содержимое уходит под панель.
        //
        // # Почему этот экран починен ВТОРЫМ, а не вместе с первым
        //
        // Я нашёл его не в жалобе, а в замере радиуса, и нашёл **после**
        // того, как починил здесь выход с клавиатуры (`760f650`):
        // жаловались на потерю веса при выходе, и я закрыл ровно то,
        // на что пожаловались.
        //
        // > **Жалоба называет один дефект, а экран несёт класс.**
        // > Померил предмет жалобы, а не экран.
        //
        // Из тринадцати слотов `} bottom: {` в приложении полями ввода
        // соседствуют **два**: этот и `TripSetupScreen`. Счёт по ТИПАМ,
        // не по файлам: греп по файлу склеил бы сюда ещё `FamilyScreen`
        // и `FoodStockScreen`, где поле живёт в шторке, а слот
        // в экране, — ошибка в сторону тревоги.
        //
        // # И почему здесь это дороже, чем в онбординге
        //
        // Черновик локальный `@State` без сохранения по выходу. Текст
        // под панелью — предупреждение об удалении одиннадцати видов
        // записей; человек, набирающий вес, его не видит.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Token.Space.s8) {
                // # Кнопка была выключена ВЕСОМ, а сохранение вес не спрашивало
                //
                // Стояло `isEnabled: draft.isValid`, а `isValid` это
                // «кличка непуста **И** `weightValue != nil`»
                // (`OnboardingFlow.swift:376`). Сохранение рядом,
                // `:226`, пишет `dog.weightKg = draft.weightValue
                // ?? dog.weightKg` — пустой вес оно переживает,
                // оставляя прежний.
                //
                // > **Условие и действие смотрели на разные величины.**
                // > Тот же класс, что у запаса корма (`d569d01`),
                // > и он дороже отсутствующей надписи: человек, стёрший
                // > вес, чтобы перенабрать, не мог сохранить и ПРАВКУ
                // > КЛИЧКИ — молчащая кнопка не говорила, какое из
                // > шести полей её держит.
                //
                // Сведено к одной величине, и величина эта — кличка:
                // так решено дизайном (ОТВЕТЫ-круг-5, п. 1) и так же
                // ведёт себя `save()`. Кнопка при этом **не
                // выключается вовсе** — правило того же пункта:
                // «иначе кнопка включена и объясняет при нажатии».
                TGButton(title: isNew ? "Добавить собаку" : "Сохранить") { готово() }
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.bottom, Token.Space.s8)
        }
        .navigationTitle(isNew ? "Новая собака" : "Профиль")
        // Строка отказа живёт до первой правки клички, а не до непустой:
        // человек уже начал исправлять, ругать его по дороге незачем.
        .onChange(of: draft.name) { _, _ in кличкаНеНазвана = false }
        .cinemaScreen()
        // Выход с цифровой клавиатуры. Худший экран этого класса:
        // см. причину у объявления `весВФокусе`.
        .готовоНадКлавиатурой { весВФокусе = false }
        .task { load() }
        .confirmationDialog("Удалить \(dog?.displayName ?? draft.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Исчезнут все одиннадцать видов записей: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки и запас корма. Это нельзя отменить.")
        }
    }

    /// Что делает «Готово».
    ///
    /// Отказ из трёх частей, и ни одна не заменяет другие: **слово**
    /// (строка под полем), **место** (фокус уезжает в кличку)
    /// и хаптика `.warning` — для того, кто смотрит не на экран.
    /// Та же тройка, что на шаге онбординга (`OnboardingSteps.swift`).
    private func готово() {
        guard !кличкаПуста else {
            кличкаНеНазвана = true
            кличкаВФокусе = true
            Haptics.warning()
            return
        }
        кличкаНеНазвана = false
        save()
    }

    private func load() {
        guard !loaded, let dog else { loaded = true; return }
        draft.name = dog.name
        draft.weight = String(dog.weightKg).replacingOccurrences(of: ".", with: ",")
        draft.breed = dog.breed ?? ""
        draft.isOnTreatment = dog.isOnTreatment
        draft.sex = dog.sex
        draft.isNeutered = dog.isNeutered
        loaded = true
    }

    private func save() {
        if let dog {
            let былоИмя = dog.name
            let былВес = dog.weightKg
            let былаПорода = dog.breed
            let былоЛечение = dog.isOnTreatment
            let былПол = dog.sex
            let былаКастрация = dog.isNeutered
            // **Кличка триммится, потому что она КЛЮЧ, а не показ.**
            //
            // Соседняя ветка того же метода (`:102`, `draft.makeDog()`)
            // триммит с первого дня, эта — нет. Пустую кличку сюда
            // не пустят ворота `готово()` (`кличкаПуста` сам триммит;
            // до 25.10 это звалось `draft.isValid` и требовало заодно
            // вес), но «Стич » с хвостовым пробелом
            // доедет до базы целиком. А `Dog.name` дальше идёт ключом
            // группировки — `DuplicateMerge.swift:38` и карточка
            // дублей, — то есть «Стич» и «Стич » станут двумя собаками,
            // и предложение их слить человек увидит без причины.
            //
            // > **Умолчание в ПОКАЗЕ видно человеку, умолчание в КЛЮЧЕ
            // > не видно никому.** С пробелом хуже, чем с пустотой:
            // > пустую кличку мы хотя бы прячем.
            //
            // `?? dog.name` — не перестраховка: `Fmt.dogName` отдаёт
            // `nil` на строке из одних пробелов, и затереть ею живую
            // кличку значило бы потерять собаку с экрана вместе
            // с одиннадцатью каскадами за ней.
            //
            // **Чего эта правка НЕ делает.** Она закрывает один путь
            // к мусорному ключу. Семя пустых собак из отзыва 06.10
            // не здесь: их кладёт зеркало CloudKit мимо кода
            // приложения (`DogOrigin.swift:39-41`), и сколько их
            // в живых данных — на 08.10 НЕ ИЗМЕРЕНО: съём крошек
            // с телефона отложен Викторией.
            dog.name = Fmt.dogName(draft.name) ?? dog.name
            dog.weightKg = draft.weightValue ?? dog.weightKg
            dog.breed = draft.breed.isEmpty ? nil : draft.breed
            dog.isOnTreatment = draft.isOnTreatment
            dog.sex = draft.sex
            // Кастрация привязана к полу и в показе, и в смысле: сняли
            // пол обратно в «не знаю» — утверждение «кастрирован»
            // осталось бы висеть без того, к чему относится, и уехало бы
            // в сводку врачу молча. Строка исчезает с экрана вместе
            // с полом, значит и значение не должно её пережить.
            dog.isNeutered = draft.sex == .unknown ? false : draft.isNeutered
            guard context.persist(otherwise: {
                dog.name = былоИмя
                dog.weightKg = былВес
                dog.breed = былаПорода
                dog.isOnTreatment = былоЛечение
                dog.sex = былПол
                dog.isNeutered = былаКастрация
            }) else { return неСохранилось() }
        } else {
            let new = draft.makeDog()
            context.insert(new)
            SeedData.attachStarterCare(to: new, context: context)
            // Сохраняем сразу и сразу открываем: заводят вторую собаку,
            // чтобы на неё смотреть, а не чтобы она лежала в списке.
            //
            // Выбор ставится только после удачи: `appState.select` звался
            // после `try?`, и приложение могло открыть собаку, которой
            // нет в хранилище.
            guard context.persist(otherwise: { context.delete(new) }) else {
                return неСохранилось()
            }
            DogOrigin.заведенаЗдесь(new.id)
            appState.select(new)
        }
        Haptics.success()
        dismiss()
    }

    /// Экран остаётся открытым: закрыть его значило бы сказать «готово»
    /// о том, чего в дневнике нет. Введённое никуда не делось — человек
    /// нажимает «Готово» ещё раз.
    private func неСохранилось() {
        Haptics.warning()
        appState.showFailure("Не сохранилось · нажми «Готово» ещё раз")
    }

    /// Удалить собаку.
    ///
    /// Если удалили ту, что была открыта, выбор снимается: `activeDog`
    /// вернёт первую из оставшихся, а не будет держаться за пустоту.
    private func delete() {
        guard let dog else { return }
        let былВыбран = appState.activeDogID
        if appState.activeDogID == dog.id { appState.activeDogID = nil }
        context.delete(dog)
        // Снятый выбор возвращаем: иначе при неудавшемся удалении собака
        // осталась бы в дневнике, но перестала быть открытой — и человек
        // решил бы, что удаление прошло.
        guard context.persist(otherwise: { appState.activeDogID = былВыбран }) else {
            Haptics.warning()
            appState.showFailure("Не удалилось · нажми ещё раз")
            return
        }
        Haptics.warning()
        dismiss()
    }
}

/// Напоминание об уходе: завести своё или убрать лишнее.
struct CareTaskEditorSheet: View {
    var task: CareTask?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var detail = ""
    @State private var intervalDays = 30
    @State private var kind: CareKind = .periodic
    @State private var scheduledDate = Date()
    @State private var remindDaysBefore = 14
    @State private var lastDone: Date?
    @State private var category: CareCategory = .grooming
    @State private var isSeasonal = false
    @State private var seasonStart = 4
    @State private var seasonEnd = 10
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    private var isNew: Bool { task == nil }

    var body: some View {
        TGSheet(
            title: isNew ? "Новое напоминание" : .готовая(title),
            subtitle: "придёт утром вместе с остальным, а не отдельно",
            closeTitle: isNew ? "Отмена" : "Закрыть",
            hasUnsavedChanges: isNew && !title.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            TGCard(spacing: 0) {
                LabeledField(label: "Что делаем") {
                    TextField("Когти", text: $title)
                }
                TGDivider()
                LabeledField(label: "Пояснение") {
                    TextField("когда стучат по полу", text: $detail)
                }
            }

            TGCard {
                TGSectionHeader(title: "какого сорта дело",
                                subtitle: "от этого зависит, как оно себя ведёт")
                TGChipGroup(items: CareKind.allCases, title: \.title,
                            isSelected: { $0 == kind }) { kind = $0 }
                TGExplainer(text: .готовая(kindExplainer))
            }

            switch kind {
            case .daily:
                EmptyView()
            case .periodic:
                TGCard(spacing: 0) {
                    Stepper(value: $intervalDays, in: 1...365) {
                        HStack {
                            Text("Как часто").textStyle(AppFont.body)
                            Spacer()
                            Text("раз в \(Fmt.days(intervalDays))").textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    Toggle(isOn: Binding(get: { lastDone != nil },
                                         set: { lastDone = $0 ? Date() : nil })) {
                        VStack(alignment: .leading, spacing: Token.Space.s2) {
                            Text("Уже делали").textStyle(AppFont.body)
                            Text("иначе срок неизвестен — и приложение так и скажет")
                                .textStyle(AppFont.caption)
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    if lastDone != nil {
                        TGDivider()
                        DatePicker("Последний раз",
                                   selection: Binding(get: { lastDone ?? Date() },
                                                      set: { lastDone = $0 }),
                                   in: ...Date(), displayedComponents: .date)
                            .frame(minHeight: Token.Size.tapTarget)
                    }
                }
            case .dated:
                TGCard(spacing: 0) {
                    DatePicker("Когда", selection: $scheduledDate, displayedComponents: .date)
                        .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    // «Напомним заранее» было написано в пояснении, а на
                    // сколько именно — задать было негде: поле в модели
                    // стояло на четырнадцати днях и не менялось никогда.
                    // Прививку и визит к врачу планируют по-разному.
                    Stepper(value: $remindDaysBefore, in: 0...60, step: 1) {
                        HStack {
                            Text("Напомнить за").textStyle(AppFont.body)
                            Spacer()
                            Text(remindDaysBefore == 0 ? "в день визита" : Fmt.days(remindDaysBefore))
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    TGDivider()
                    Stepper(value: $intervalDays, in: 0...730, step: 30) {
                        HStack {
                            Text("Повторять").textStyle(AppFont.body)
                            Spacer()
                            Text(intervalDays == 0 ? "один раз" : "раз в \(Fmt.days(intervalDays))")
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }

            TGCard {
                TGSectionHeader(title: "куда положить")
                TGChipGroup(items: CareCategory.allCases, title: \.title,
                            isSelected: { $0 == category }) { category = $0 }
            }

            if kind != .daily {
            TGCard {
                Toggle(isOn: $isSeasonal) {
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text("Только в сезон").textStyle(AppFont.body)
                        Text("вне сезона напоминание молчит").textStyle(AppFont.caption)
                    }
                }
                if isSeasonal {
                    HStack {
                        Picker("С", selection: $seasonStart) {
                            ForEach(1...12, id: \.self) { Text(месяц($0)).tag($0) }
                        }
                        Picker("По", selection: $seasonEnd) {
                            ForEach(1...12, id: \.self) { Text(месяц($0)).tag($0) }
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            }

            if !isNew {
                TGButton(title: "Удалить напоминание", variant: .destructive, size: .medium, systemImage: "trash") {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Образец формы — запас корма (`d569d01`):
            // строка над кнопкой, той же величиной, что и ворота.
            VStack(spacing: Token.Space.s8) {
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Назови напоминание — под этим именем оно встанет в список")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: isNew ? "Добавить" : "Сохранить",
                         isEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            }
        }
        .presentationDetents([.large])
        .task { load() }
        .confirmationDialog("Удалить «\(title)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let task { context.delete(task) }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Напоминание перестанет приходить по утрам. Записи о том, что уже сделано, останутся в истории.")
        }
    }

    private var kindExplainer: String {
        switch kind {
        case .daily:
            String(localized: "Привычка. Просрочки у неё нет — есть серия дней подряд. Зубы чистят каждый день: налёт твердеет за сутки.")
        case .periodic:
            String(localized: "Раз в N дней от последнего раза. Пока ни разу не делали, срок неизвестен, и приложение не станет выдумывать просрочку.")
        case .dated:
            String(localized: "Конкретный день: прививка, визит. Напомним заранее и сдвинем дату на следующий раз.")
        }
    }

    private func месяц(_ number: Int) -> String {
        DateFormatter().monthSymbols?[number - 1].capitalized ?? "\(number)"
    }

    private func load() {
        guard !loaded, let task else { loaded = true; return }
        title = task.title
        detail = task.detail
        kind = task.kind
        intervalDays = task.intervalDays
        scheduledDate = task.scheduledDate ?? Date()
        remindDaysBefore = task.remindDaysBefore
        lastDone = task.lastDone
        category = task.category
        isSeasonal = task.seasonStartMonth != nil
        seasonStart = task.seasonStartMonth ?? 4
        seasonEnd = task.seasonEndMonth ?? 10
        loaded = true
    }

    private func save() {
        let target = task ?? CareTask(title: title, detail: detail, kind: kind,
                                      intervalDays: intervalDays, category: category)
        // Снимок до правки: при отказе сохранения поля обязаны вернуться,
        // иначе экран закроется, а изменённое напоминание останется висеть
        // в памяти, не существуя в хранилище. `rollback()` для этого
        // не годится — измерено, см. `SilentFailureTests`.
        let былоНазвание = target.title
        let былоОписание = target.detail
        let былВид = target.kind
        let былИнтервал = target.intervalDays
        let былаКатегория = target.category
        let былоСделано = target.lastDone
        let былаДата = target.scheduledDate
        let былоЗаранее = target.remindDaysBefore
        let былоНачалоСезона = target.seasonStartMonth
        let былКонецСезона = target.seasonEndMonth

        target.title = title
        target.detail = detail
        target.kind = kind
        target.intervalDays = intervalDays
        target.category = category
        target.lastDone = kind == .daily ? target.lastDone : lastDone
        target.scheduledDate = kind == .dated ? scheduledDate : nil
        target.remindDaysBefore = remindDaysBefore
        target.seasonStartMonth = (isSeasonal && kind != .daily) ? seasonStart : nil
        target.seasonEndMonth = (isSeasonal && kind != .daily) ? seasonEnd : nil
        let новое = task == nil
        if новое {
            target.dog = dog
            context.insert(target)
        }

        guard context.persist(otherwise: {
            if новое {
                target.dog = nil
                context.delete(target)
            } else {
                target.title = былоНазвание
                target.detail = былоОписание
                target.kind = былВид
                target.intervalDays = былИнтервал
                target.category = былаКатегория
                target.lastDone = былоСделано
                target.scheduledDate = былаДата
                target.remindDaysBefore = былоЗаранее
                target.seasonStartMonth = былоНачалоСезона
                target.seasonEndMonth = былКонецСезона
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}

/// Схема лечения. Меняет её только владелец — остальные видят и исполняют.
struct MedicationEditorSheet: View {
    var medication: Medication?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var doseText = ""
    @State private var times: [Int] = [7 * 60]
    @State private var fastingMinutes = 0
    @State private var fastingBeforeMinutes = 0
    @State private var prescriber = ""
    /// Масса вещества в одной единице формы. Вводится ЧИСЛОМ и ЕДИНИЦЕЙ,
    /// хранится всегда в микрограммах — перевод случается здесь и больше
    /// нигде.
    @State private var массаТекст = ""
    @State private var даётсяНаУлице = false
    @State private var массаЕдиница: ЕдиницаМассы = .мкг
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    /// Фокус поля массы — единственного `.decimalPad` в этом листе.
    @FocusState private var массаВФокусе: Bool

    private var isNew: Bool { medication == nil }

    var body: some View {
        TGSheet(
            title: isNew ? "Новый препарат" : .готовая(name),
            subtitle: "доза по часам — одна из трёх вещей, которым можно прерывать человека",
            closeTitle: isNew ? "Отмена" : "Закрыть",
            hasUnsavedChanges: isNew && !(name + doseText + prescriber)
                .trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            TGCard(spacing: 0) {
                LabeledField(label: "Название") {
                    TextField("Lévothyrox", text: $name)
                }
                TGDivider()
                LabeledField(label: "Доза") {
                    TextField("доза с единицей", text: $doseText)
                }
                TGDivider()
                LabeledField(label: "Назначил") {
                    TextField("врач или клиника", text: $prescriber)
                }
            }

            TGCard {
                TGSectionHeader(title: "сколько вещества в одной единице")
                HStack(spacing: Token.Space.s8) {
                    // Единица выбирается Picker'ом СПРАВА, поэтому
                    // подсказка говорит ровно то, чего пример «66»
                    // не говорил: единицу сюда не писать.
                    TextField("только число", text: $массаТекст)
                        .keyboardType(.decimalPad)
                        .focused($массаВФокусе)
                        .autocorrectionDisabled()
                        .textStyle(AppFont.body)
                    Picker("Единица", selection: $массаЕдиница) {
                        ForEach(ЕдиницаМассы.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                }
                .frame(minHeight: Token.Size.tapTarget)
                // **Поле нужно графику, а не учёту запаса.** Без него
                // линия Т4 и доза рядом не читаются: счёт таблеток
                // не меняется, когда врач меняет силу таблетки,
                // и рост дозы становится невидимым.
                //
                // Пусто оставить МОЖНО: это «не введено», а не ноль.
                // Тогда график покажет точки без столбиков дозы
                // и скажет об этом словами, а не нарисует ноль.
                TGExplainer(text: "Нужно графику: по силе таблетки видно, росла ли доза. Можно оставить пустым — тогда график покажет анализы без дозы и скажет об этом.")
            }

            TGCard {
                TGSectionHeader(title: "во сколько давать")
                ForEach(times.indices, id: \.self) { index in
                    HStack {
                        Picker("Час", selection: Binding(
                            get: { times[index] / 60 },
                            set: { times[index] = $0 * 60 + times[index] % 60 }
                        )) {
                            ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Минуты", selection: Binding(
                            get: { times[index] % 60 },
                            set: { times[index] = (times[index] / 60) * 60 + $0 }
                        )) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        if times.count > 1 {
                            Button {
                                times.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Token.Status.overdueText)
                            }
                            .accessibilityLabel("Убрать время")
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGButton(title: "Добавить время", variant: .secondary, size: .medium, systemImage: "plus") {
                    times.append(19 * 60)
                }
            }

            TGCard {
                // Два окна, а не одно. «Натощак» — это про пустой желудок,
                // а пустым он бывает ДО таблетки; раньше здесь стояла
                // только половина правила, и схема «еда в 20:55, доза
                // в 21:00» проходила проверку целиком.
                Stepper(value: $fastingBeforeMinutes, in: 0...180, step: 15) {
                    HStack {
                        Text("Не кормить до приёма").textStyle(AppFont.body)
                        Spacer()
                        Text(fastingBeforeMinutes == 0 ? "не нужно" : "\(fastingBeforeMinutes) мин")
                            .textStyle(AppFont.numeric(15))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Stepper(value: $fastingMinutes, in: 0...180, step: 15) {
                    HStack {
                        Text("Не кормить после приёма").textStyle(AppFont.body)
                        Spacer()
                        Text(fastingMinutes == 0 ? "не нужно" : "\(fastingMinutes) мин")
                            .textStyle(AppFont.numeric(15))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Пока окно идёт, кнопка еды не исчезает — она объясняет причину и предлагает напомнить, когда можно.")
            }

            // Писатель для `Medication.canGiveOutside` (`Care.swift:402`).
            //
            // **До 08.10.2026 у поля не было ни одного писателя в `Togo/`.**
            // Оно есть в модели, ездит в обмене, хранится в архиве,
            // и `WalkDose` его ЧИТАЕТ — то есть «эту можно дать
            // на улице» не показалось бы никогда.
            //
            // > **Поле без писателя и отсутствующее поле — разные вещи,
            // > и снаружи они неразличимы.** Второе видно как дыра,
            // > первое — как работающая функция.
            //
            // **Спрашиваем, а НЕ выводим.** Ни из `fastingBefore`,
            // ни из `dependsOnMeal`, ни из `unit == .ml`: таблетку
            // с едой носят в кармане с кормом, сироп бывает шприцем
            // в сумке.
            //
            // > **У выведенного признака две причины, которые нечем
            // > различить: «мы посчитали» и «она так сказала» выглядят
            // > одинаково.** Довод вырос из четырёх полей, которые
            // > в этот же день оставили пустыми по той же причине, —
            // > время забора, вес у рецепта, норма с бланка, предел
            // > прибора.
            //
            // `false` по умолчанию верно и по цене ошибки: предложить
            // дать дозу на улице там, где нельзя, дороже, чем
            // не предложить там, где можно.
            TGCard {
                Toggle(isOn: $даётсяНаУлице) {
                    Text("Можно дать на улице").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Включи, если носишь эту дозу с собой. Тогда в режиме прогулки появится «Дал» — и отметка не потеряется до дома. Не включай, если дозу дают только дома: приложение не станет предлагать.")
            }

            if let medication {
                TGCard {
                    Toggle(isOn: Binding(get: { medication.isPaused }, set: { medication.isPaused = $0 })) {
                        Text("Поставить на паузу").textStyle(AppFont.body)
                    }
                    TGExplainer(text: "Пауза оставляет схему в истории и в отчёте врачу — в отличие от удаления.")
                }
                TGButton(title: "Удалить схему", variant: .destructive, size: .medium, systemImage: "trash") {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Форма — по образцу запаса корма (`d569d01`):
            // строка над кнопкой, на ТОЙ ЖЕ величине, что ворота.
            VStack(spacing: Token.Space.s8) {
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Назови препарат — остальное можно заполнить потом")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: isNew ? "Добавить" : "Сохранить",
                         isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            }
        }
        .presentationDetents([.large])
        // Выход с цифровой клавиатуры. Это ЛИСТ, а не экран: панель
        // `.keyboard` привязана к клавиатуре, не к навигационной
        // полосе, поэтому `NavigationStack` ей не нужен — но здесь
        // это не измерено, а взято из устройства SwiftUI, и проверять
        // лист надо отдельно от экрана.
        .готовоНадКлавиатурой { массаВФокусе = false }
        .task { load() }
        .confirmationDialog("Удалить схему «\(name)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let medication { context.delete(medication) }
                Haptics.warning()
                dismiss()
            }
            Button("Поставить на паузу") {
                medication?.isPaused = true
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Удаление уберёт схему и её приёмы из отчёта врачу. Пауза оставит всё в истории — обычно нужна именно она.")
        }
    }

    private func load() {
        guard !loaded, let medication else { loaded = true; return }
        name = medication.name
        doseText = medication.doseText
        times = medication.times.isEmpty ? [7 * 60] : medication.times
        fastingMinutes = medication.fastingMinutes
        // У схемы, заведённой до появления поля, окно «до» читается
        // симметрично — показываем то же, что и применяем.
        fastingBeforeMinutes = medication.fastingBefore
        prescriber = medication.prescriber ?? ""
        // Показываем в той единице, в которой число читается человеком,
        // а храним всегда в микрограммах.
        if let мкг = medication.massPerUnitMcg, мкг > 0 {
            if мкг < 1000 {
                массаЕдиница = .мкг
                массаТекст = ЧислоСБланка.текст(мкг)
            } else {
                массаЕдиница = .мг
                массаТекст = ЧислоСБланка.текст(мкг / 1000)
            }
        }
        даётсяНаУлице = medication.canGiveOutside
        loaded = true
    }

    private func save() {
        let target = medication ?? Medication(name: name, doseText: doseText, times: times, fastingMinutes: fastingMinutes)
        // Снимок до правки. Здесь цена молчания выше, чем у остальных
        // редакторов: часы приёма и окно натощак — это расписание доз
        // и напоминаний. Экран, закрывшийся с «получилось» после
        // несохранённой правки, обещает лечение по новому расписанию,
        // а телефон продолжает напоминать по старому.
        let былоИмя = target.name
        let былаДоза = target.doseText
        let былиЧасы = target.times
        let былоНатощак = target.fastingMinutes
        let былоНатощакДо = target.fastingBeforeMinutes
        let былВрач = target.prescriber
        let былаМасса = target.massPerUnitMcg
        let былоНаУлице = target.canGiveOutside

        target.name = name
        target.doseText = doseText
        target.times = times.sorted()
        target.fastingMinutes = fastingMinutes
        target.fastingBeforeMinutes = fastingBeforeMinutes
        target.prescriber = prescriber.isEmpty ? nil : prescriber
        // Разбор — `ЧислоСБланка`, уже заведённый для анализов: он терпит
        // и запятую, и точку, и неразрывные пробелы из PDF. Второго
        // разбора числа в проекте заводить нельзя — они разойдутся
        // на второй правке.
        //
        // ЕДИНСТВЕННОЕ место перевода на вводе: число × множитель
        // единицы → микрограммы. Пустая строка даёт `nil` — «не
        // введено», а не ноль.
        target.massPerUnitMcg = ЧислоСБланка.разобрать(массаТекст).map { $0 * массаЕдиница.вМикрограммах }
        target.canGiveOutside = даётсяНаУлице
        let новое = medication == nil
        if новое {
            target.dog = dog
            context.insert(target)
        }

        guard context.persist(otherwise: {
            if новое {
                target.dog = nil
                context.delete(target)
            } else {
                target.name = былоИмя
                target.doseText = былаДоза
                target.times = былиЧасы
                target.fastingMinutes = былоНатощак
                target.fastingBeforeMinutes = былоНатощакДо
                target.prescriber = былВрач
                target.massPerUnitMcg = былаМасса
                target.canGiveOutside = былоНаУлице
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
