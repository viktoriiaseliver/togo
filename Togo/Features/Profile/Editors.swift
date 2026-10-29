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
                // # Вес правится в одном месте — на экране «Вес» (29.10.2026)
                //
                // Аудит вкладки собаки: вес правили два экрана по разным
                // правилам. Здесь `save()` писал `dog.weightKg` голым
                // присваиванием, мимо взвешиваний, а «Вес» считает текущим
                // вес ПОСЛЕДНЕГО ЗАМЕРА (`WeightScreen.delete`,
                // `WeightEntryEditorSheet`). Число, набранное в профиле,
                // жило до первой правки или удаления любого взвешивания —
                // и молча пропадало, а от веса считается доза.
                //
                // Решение Виктории («да все чини»): у заведённой собаки —
                // дверь на «Вес», у новой — поле остаётся, и вес уезжает
                // первым взвешиванием (`SeedData.attachStarterCare`), то
                // есть тем же путём, что у онбординга.
                if let dog {
                    TGLink(title: "Вес", value: .готовая(Fmt.weight(dog.weightKg)),
                           systemImage: "scalemass") { WeightScreen(dog: dog) }
                } else {
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
                }
                TGDivider()
                LabeledField(label: "Порода") {
                    TextField("можно пропустить", text: $draft.breed)
                }
                TGDivider()
                // # Дату рождения хранили, а спросить её было негде
                //
                // Замер 29.10.2026: `Dog.birthDate` ездит в обмене,
                // в архиве и в сводке врачу (`ageMonths`), а писатель
                // у неё в `Togo/` один — `DogDraft.makeDog()`. Поля
                // `hasBirthDate`/`birthDate` в черновике лежат с первого
                // дня, но с 28-го макета онбординг их не показывает,
                // а профиль не показывал никогда — то есть возраст
                // не мог назвать НИКТО, ни при заведении, ни потом.
                //
                // Тумблер отдельно от даты по той же причине, что
                // у сроков лекарства (`MedicationEditorSheet`):
                // `DatePicker` пустого значения не умеет, и без
                // «знаю» первое же открытие профиля записало бы
                // собаке днём рождения сегодняшнее число.
                Toggle(isOn: Binding(
                    get: { draft.hasBirthDate },
                    set: { знаю in
                        draft.hasBirthDate = знаю
                        if знаю, draft.birthDate == nil { draft.birthDate = Date() }
                    }
                )) {
                    Text("Знаю дату рождения").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if draft.hasBirthDate {
                    DatePicker("Дата рождения",
                               selection: Binding(get: { draft.birthDate ?? Date() },
                                                  set: { draft.birthDate = $0 }),
                               in: ...Date(), displayedComponents: .date)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
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

            // # Тумблер лечения — только у НОВОЙ собаки (29.10.2026)
            //
            // У заведённой он был вторым на тот же флаг, и с другим
            // правилом. Профиль (`ProfileScreen.treatment`) зовёт
            // `TreatmentCourse.finish`/`resume`: выключение отменяет схемы
            // и гасит будущие дозы, включение возвращает отменённые курсом.
            // Здесь же `save()` писал `dog.isOnTreatment = …` голым
            // присваиванием — курс «закрывался», а схемы продолжали звать
            // дозы, ровно то, от чего предостерегает комментарий профиля
            // («схема оживала наполовину»). И право было не то:
            // `editProfile` вместо `editTreatment`.
            //
            // Профиль — один экран назад, тумблер там на месте; у новой
            // собаки схем нет, и голый флаг ей законен.
            //
            // Подпись заменена: «включит вкладку „Здоровье“» — неправда
            // с 08.10.2026 (`02c1e88`): вкладку держит право `seeMedical`,
            // а не курс. Взята подпись профиля — одно и то же действие
            // теперь называется одними словами.
            if isNew {
                TGCard {
                    Toggle(isOn: $draft.isOnTreatment) {
                        VStack(alignment: .leading, spacing: Token.Space.s2) {
                            Text("Собака на лечении").textStyle(AppFont.body)
                            Text("включает дозы по часам, окно натощак и напоминания").textStyle(AppFont.caption)
                        }
                    }
                }
            }

            if !isNew {
                TGCard {
                    TGSectionHeader(title: "убрать")
                    TGButton(title: "Удалить собаку", variant: .destructive, size: .medium, systemImage: "trash") {
                        isConfirmingDelete = true
                    }
                    // # Текст обещал стирание, а код ставит надгробие (29.10.2026)
                    //
                    // Здесь и в диалоге стояло «исчезнет весь её
                    // дневник… одиннадцать видов… Это нельзя отменить».
                    // `delete()` ниже зовёт `ОбщееУдаление.удалить(dog)`:
                    // собака получает `deletedAt`, каскад НЕ ходит,
                    // записи остаются в базе телефона невидимыми.
                    // То есть «исчезнет» было неправдой про базу,
                    // а перечень — неполным: медкнижка (анализы,
                    // визиты, диагнозы, рецепты) — четыре связи
                    // `Dog` с каскадом, и в списке её не было вовсе.
                    //
                    // Теперь текст говорит, что видно человеку
                    // («пропадёт из дневника»), перечисляет все
                    // пятнадцать видов, а стирание насовсем называет
                    // по месту, где оно правда есть.
                    TGExplainer(text: "Вместе с ней из дневника пропадёт всё, что про неё записано: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки, запас корма, анализы, визиты, диагнозы и рецепты. Выгрузить дневник можно в «Настройки → Данные и приватность».")
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
        .cinemaScreen(экран: .sub("editors"))
        // Выход с цифровой клавиатуры. Худший экран этого класса:
        // см. причину у объявления `весВФокусе`.
        .готовоНадКлавиатурой { весВФокусе = false }
        .task { load() }
        // # ОТМЕНА БЕЗ РОЛИ — ИНАЧЕ ЕЁ НЕ РИСУЮТ ВОВСЕ
        //
        // Замер 26.10.2026, четыре канала: поддерево листа,
        // `app.buttons` по всему дереву, пиксели, глаза человека —
        // кнопки отмены НЕТ НИ В ОДНОМ. Диалог выходит узким пузырём
        // с хвостиком (рамка `(81, 72, 240, 312)` при экране 402),
        // и в нём ровно одна красная кнопка «Удалить» над текстом
        // «Это нельзя отменить».
        //
        // **Это не особенность экрана.** Контрольный диалог на другом
        // экране (`DataPrivacyScreen`, «Удалить все данные?») в том же
        // прогоне дал `(81, 72, 240, 212)` и `["Удалить всё"]` — та же
        // точка, та же ширина, та же единственная кнопка.
        //
        // Что ИСКЛЮЧЕНО замерами, чтобы следующий не искал заново:
        //
        // ```
        // horizontalSizeClass в момент показа   .compact  (замерено, log.notice)
        // .popover                              0 вхождений
        // presentationCompactAdaptation         0 вхождений
        // оба экрана показаны                   push в NavigationStack, не sheet
        // общий модификатор cinemaScreen()      только toolbar и background
        // ```
        //
        // **Механизм НЕ УСТАНОВЛЕН** — «не у нас и не от класса
        // размера» это исчерпание нашей стороны, а не причина.
        // Но починка от него не зависит: человеку нужен выход,
        // и дать его надо СВОИМ средством.
        //
        // > **Роль `.cancel` — ровно то, чего popover не рисует.**
        // > Обычную кнопку он рисует. Поэтому роль снята, а не заменён
        // > весь диалог: `alert` сменил бы поведение всех соседей,
        // > и прецедента нет — `.alert(` в проекте ноль вхождений.
        //
        // Цена снятия роли названа и принята: кнопка теряет позицию
        // и выделение, которые система даёт роли. **Выход, который
        // видно, дороже выхода, который правильно оформлен.**
        .confirmationDialog("Удалить \(dog?.displayName ?? draft.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена") {}
        } message: {
            Text("Из дневника пропадут она и все её записи: отметки, взвешивания, дела ухода, схемы лечения с дозами, шаги и занятия, поездки, документы, выезды, течки, запас корма, анализы, визиты, диагнозы и рецепты. Вернуть её из приложения нельзя. Стереть с телефона насовсем — «Данные и приватность → Удалить все данные».")
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
        // Вес в черновик больше не читается: у заведённой собаки поля
        // веса здесь нет, вместо него дверь на «Вес» (29.10.2026).
        draft.breed = dog.breed ?? ""
        draft.isOnTreatment = dog.isOnTreatment
        draft.sex = dog.sex
        draft.isNeutered = dog.isNeutered
        draft.hasBirthDate = dog.birthDate != nil
        draft.birthDate = dog.birthDate
        loaded = true
    }

    private func save() {
        if let dog {
            let былоИмя = dog.name
            let былаПорода = dog.breed
            let былПол = dog.sex
            let былаКастрация = dog.isNeutered
            let былаДатаРождения = dog.birthDate
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
            // `dog.weightKg` здесь больше не пишется: текущий вес — вес
            // последнего взвешивания, и меняет его только экран «Вес»
            // (разбор — у двери на него выше, 29.10.2026).
            dog.breed = draft.breed.isEmpty ? nil : draft.breed
            // `isOnTreatment` здесь больше не пишется: курс у заведённой
            // собаки меняет только `TreatmentCourse` (разбор — у тумблера).
            dog.sex = draft.sex
            // Кастрация привязана к полу и в показе, и в смысле: сняли
            // пол обратно в «не знаю» — утверждение «кастрирован»
            // осталось бы висеть без того, к чему относится, и уехало бы
            // в сводку врачу молча. Строка исчезает с экрана вместе
            // с полом, значит и значение не должно её пережить.
            dog.isNeutered = draft.sex == .unknown ? false : draft.isNeutered
            // Начало дня, а не момент: день рождения — это день. Час,
            // в который человек открыл профиль, о собаке ничего не говорит.
            dog.birthDate = draft.hasBirthDate
                ? draft.birthDate.map { Calendar.current.startOfDay(for: $0) }
                : nil
            guard context.persist(otherwise: {
                dog.name = былоИмя
                dog.breed = былаПорода
                dog.sex = былПол
                dog.isNeutered = былаКастрация
                dog.birthDate = былаДатаРождения
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
        // Надгробие вместо `context.delete`. Каскад при этом НЕ ходит,
        // и это решение: надгробие на собаке значит «этой собаки у нас
        // нет», а не «сотрите её историю у второго человека». Жёсткое
        // удаление уносило ленту, веса, дела, схемы и медкнижку —
        // у себя, и молча ничего не говорило второму телефону.
        let откатНадгробия = ОбщееУдаление.удалить(dog)
        // Снятый выбор возвращаем: иначе при неудавшемся удалении собака
        // осталась бы в дневнике, но перестала быть открытой — и человек
        // решил бы, что удаление прошло. Надгробие возвращаем по той же
        // причине, и она стала сильнее: фильтры показа читают ПОЛЕ,
        // а не базу, так что незаписанное надгробие убрало бы собаку
        // с экрана при отказе сохранения — отказ выглядел бы успехом.
        guard context.persist(otherwise: {
            appState.activeDogID = былВыбран
            откатНадгробия()
        }) else {
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
    /// Три поля прививки (`CareTask.vaccineBatch`, `vaccineValidUntil`,
    /// `clinic`). Замер 29.10.2026: все три ездят в обмене и в архиве,
    /// а пишет их в `Togo/` только прогрев схемы CloudKit — человеку
    /// ввести партию с наклейки было негде, хотя повод у полей назван
    /// днём (срок бешенства Стича истёк 03.10.2026, `Care.swift:16`).
    @State private var партия = ""
    @State private var естьДействуетДо = false
    @State private var действуетДо = Date()
    @State private var клиника: Clinic?
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    @Query private var всеКлиники: [Clinic]

    /// Где делали — клиники без лабораторий, и выбранная остаётся
    /// в списке всегда. Правило и его причина взяты у `VetVisitEditor`:
    /// без этого правка старой прививки молча стёрла бы организацию.
    private var доступныеКлиники: [Clinic] {
        let живые = всеКлиники.filter { $0.deletedAt == nil && !$0.isLab }
        let выбранная = клиника.map { [$0] } ?? []
        let слитые = живые + выбранная.filter { выбор in
            !живые.contains { $0.persistentModelID == выбор.persistentModelID }
        }
        return слитые.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Поля прививки показываются у медицинских дел, кроме ежедневных:
    /// прививка — дело «по дате» или «раз в N дней», а у груминга
    /// партии и срока с наклейки не бывает.
    private var спрашиватьПрививку: Bool { category == .medical && kind != .daily }

    private var isNew: Bool { task == nil }

    var body: some View {
        TGSheet(
            title: isNew ? "Новое напоминание" : .готовая(title),
            // «придёт утром» было верно, пока час сводки выбирался
            // из 5…12. С 28.10.2026 выбирается часть дня — и строка
            // обещала бы утро тому, кто поставил вечер.
            subtitle: "придёт в выбранный час вместе с остальным, а не отдельно",
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

            if спрашиватьПрививку {
                прививкаКарточка
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
                // Надгробие вместо `context.delete`: иначе у второго
                // человека дело остаётся, и «план дня» у двоих разный.
                if let task {
                    let откат = ОбщееУдаление.удалить(task)
                    guard context.persist(otherwise: откат) else {
                        Haptics.warning()
                        appState.showFailure("Не удалилось · нажми ещё раз")
                        return
                    }
                }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Напоминание перестанет приходить по утрам. Записи о том, что уже сделано, останутся в истории.")
        }
    }

    /// Партия, срок и клиника — то, что стоит на наклейке в паспорте.
    ///
    /// Всё необязательное и пустое по умолчанию: подставить срок
    /// значило бы напечатать человеку дату, которой он не вводил,
    /// а запись потом читает врач (красная линия «не подставлять»).
    private var прививкаКарточка: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: "если это прививка", subtitle: "с наклейки в паспорте")
            LabeledField(label: "Партия") {
                TextField("как в документе", text: $партия)
                    .autocorrectionDisabled()
            }
            TGDivider()
            Toggle(isOn: $естьДействуетДо) {
                Text("Срок годности указан").textStyle(AppFont.body)
            }
            .frame(minHeight: Token.Size.tapTarget)
            if естьДействуетДо {
                DatePicker("Годен до", selection: $действуетДо, displayedComponents: .date)
                    .textStyle(AppFont.body)
                    .frame(minHeight: Token.Size.tapTarget)
            }
            TGDivider()
            Picker("Клиника", selection: $клиника) {
                Text("не указана").tag(nil as Clinic?)
                ForEach(доступныеКлиники) { Text(verbatim: $0.name).tag($0 as Clinic?) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Token.Size.tapTarget)
            if доступныеКлиники.isEmpty {
                TGExplainer(text: "Справочник пуст. Клиники и лаборатории заводятся в «Здоровье» → «Клиники и лаборатории» — оттуда они и попадают в этот выбор.")
            }
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
        партия = task.vaccineBatch ?? ""
        естьДействуетДо = task.vaccineValidUntil != nil
        действуетДо = task.vaccineValidUntil ?? Date()
        клиника = task.clinic
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
        let былаПартия = target.vaccineBatch
        let былоДействуетДо = target.vaccineValidUntil
        let былаКлиника = target.clinic

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
        // Пишем, только когда поля были на экране. Скрытая карточка
        // (дело переложили в груминг) не повод стирать партию молча:
        // поле, которое человек не видел, он и не менял.
        if спрашиватьПрививку {
            target.vaccineBatch = Fmt.notBlank(партия)
            target.vaccineValidUntil = естьДействуетДо ? действуетДо : nil
            target.clinic = клиника
        }
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
                target.vaccineBatch = былаПартия
                target.vaccineValidUntil = былоДействуетДо
                target.clinic = былаКлиника
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
    /// Часы приёма И количество на каждый час — **одним массивом,
    /// а не двумя**.
    ///
    /// Здесь раньше жил `times: [Int]`, и количество ввести было нечем:
    /// `Medication.doseSlotsData` не писал ни один экран (замер
    /// 26.10.2026), хотя читателей у него двое и оба живые —
    /// `dailyUse` (запас на экране «Здоровье») и `quantity(at:)`
    /// (списание с отметки приёма в `DoseScheduler.markGiven`).
    /// Без ввода «½ утром, 1 вечером» оба считали по единице за приём,
    /// то есть расход вдвое больше настоящего, и запас кончался
    /// на бумаге раньше, чем в пачке.
    ///
    /// Второй массив рядом с `times` завести нельзя, и причина записана
    /// в самой модели: два параллельных массива разъезжаются длинами
    /// молча, и тогда половина таблетки приземляется на чужой час.
    /// У `DoseSlot` разъезжаться нечем — час и количество в одной
    /// записи. Правило взято там же, где оно уже записано, а не
    /// придумано здесь заново.
    @State private var слоты: [DoseSlot] = [DoseSlot(minuteOfDay: 7 * 60, quantity: 1)]
    @State private var единица: MedUnit = .tab
    @State private var fastingMinutes = 0
    @State private var fastingBeforeMinutes = 0
    /// Писатель для `Medication.minutesAfterMeal` (`Care.swift:337`).
    ///
    /// Замер 29.10.2026: поле читают `DoseGate` (замок дозы до еды),
    /// `DoseGateSheet` (объяснение замка), обмен и архив — а писали
    /// его только засев и откат архива. Инсулин, который колют
    /// через N минут после еды, завести человеку было нечем.
    @State private var послеЕдыМинут = 0
    @State private var prescriber = ""
    @State private var номерНазначения = ""
    /// Сроки — каждый со своим «указан ли». `nil` в модели значит
    /// «не введено», и тумблер — единственный способ отличить его
    /// от сегодняшней даты, которую `DatePicker` подставит сам.
    /// С какого дня даём — `Medication.startedAt`, V8. У новой схемы
    /// по умолчанию сегодня и названо: человек заводит то, что начал.
    /// Начали раньше — сдвигает дату назад (просьба Виктории 28.10.2026).
    @State private var началоНазвано = true
    @State private var началоСхемы = Date()
    /// Через сколько недель от начала сдать кровь. Каждая неделя —
    /// дело ухода «по дате» в медицинской категории.
    @State private var контрольНедели: Set<Int> = []
    @State private var естьКурсДо = false
    @State private var курсДо = Date()
    @State private var естьСрокГодности = false
    @State private var срокГодности = Date()
    @State private var вскрыт = false
    @State private var когдаВскрыли = Date()
    @State private var годенПослеВскрытияДней = 0
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
            hasUnsavedChanges: isNew && !(name + doseText + prescriber + номерНазначения)
                .trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            // **`LabeledField.label` — это `String`, а не
            // `LocalizedStringKey`, и внутри он рисуется `Text(label)`:
            // переменная типа `String` в `LocalizedStringKey`
            // не превращается, поэтому берётся дословная перегрузка
            // и подпись НЕ ПЕРЕВОДИТСЯ ВОВСЕ** (замер 26.10.2026).
            //
            // Ключи «Название», «Доза», «Назначил» в каталоге есть
            // по одному вхождению каждый — но попали они туда
            // не отсюда: единственное место, где подпись обёрнута
            // правильно, это `ClinicScreens.swift:244`
            // (`String(localized: "Название")`). Здесь и
            // в `DocumentPhotos.swift:606` стоял голый литерал.
            //
            // > **Сторож локализации мерил прокси, а не предмет.** Он
            // > спрашивает «переведён ли ключ», и был зелёным по всем
            // > пяти языкам; «показывается ли перевод» он не спрашивает
            // > нигде. Француз на медицинской форме читал три подписи
            // > по-русски при готовом французском в каталоге.
            //
            // Новых строк это не стоит: все три ключа уже переведены
            // на пять языков. Форма взята у единственного верного
            // места, а не придумана здесь.
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
                TGDivider()
                // Писатель для `Medication.prescriptionNumber`. Поле есть
                // с шага 0 медицинского слоя, ездит в обмене и в архиве,
                // и писали его только прогрев схемы CloudKit, засев
                // и галерея макетов — **человеческого писателя не было
                // ни одного** (замер 26.10.2026).
                //
                // Стоит ПОД «Назначил» нарочно: обе строки человек
                // списывает с одного бланка, и спрашивать их в разных
                // местах формы значит заставить искать бланк дважды.
                //
                // Клавиатура обычная, не цифровая: в номере бывают
                // косая черта и ведущий ноль («2026/0417», «№ 07350»),
                // и `.numberPad` их бы не дал. Ведущий ноль значащий —
                // ровно поэтому поле строковое, а не числовое.
                // Обёрнуто `String(localized:)` по той же причине, что
                // три подписи выше: иначе ключа не было бы даже
                // в каталоге — голый литерал в параметре типа `String`
                // извлечение Xcode не видит, и строка не уехала бы
                // носителю вовсе.
                LabeledField(label: "Номер назначения") {
                    TextField("с бланка, если есть", text: $номерНазначения)
                        .autocorrectionDisabled()
                }
            }

            // Писатель для `Medication.unitRaw` (`Care.swift:253`).
            //
            // **Сеттер `unit` существовал, из интерфейса не звался ни
            // разу** (замер 26.10.2026): писали только засев и прогрев.
            // Единица формы — не украшение: «осталось 7» без неё ничего
            // не значит, потому что семь таблеток это неделя, а семь
            // миллилитров — один приём.
            //
            // Здесь она нужна сразу и по делу: от неё зависит шаг
            // количества в расписании ниже (`MedUnit.allowsHalves`) —
            // таблетку делят, миллилитр мера сам по себе. То есть поле
            // читается в этой же форме, а не только уезжает в базу.
            //
            // **Чего эта правка НЕ делает.** Экран «Здоровье» и шторка
            // запаса печатают «таблеток» литералом
            // (`HealthScreen:355`, `PillSupplyScreen:79`) и показывают
            // остаток голым числом (`HealthScreen:374`). Единицу они
            // теперь могут спросить у схемы, но файлы держит другая
            // сессия — названо вслух и отдано менеджеру.
            TGCard {
                TGSectionHeader(title: "в чём меряется")
                // Подпись озвучке — ТОТ ЖЕ ключ, что у заголовка
                // раздела, и это не экономия на букве: новая строка
                // здесь стоит пяти переводов, а сказать озвучке нужно
                // ровно то же, что видит глаз.
                Picker("в чём меряется", selection: $единица) {
                    ForEach(MedUnit.allCases, id: \.self) {
                        Text(verbatim: $0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "От этого зависит счёт запаса и можно ли делить дозу пополам.")
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
                ForEach(слоты.indices, id: \.self) { index in
                    слотРяд(index)
                    if index < слоты.count - 1 { TGDivider() }
                }
                TGButton(title: "Добавить время", variant: .secondary, size: .medium, systemImage: "plus") {
                    слоты.append(DoseSlot(minuteOfDay: 19 * 60, quantity: 1))
                }
                // Говорит ровно то, что считает код: расход берётся
                // суммой количеств (`Medication.dailyUse`), и запас
                // на экране «Здоровье» вычитает столько, сколько дали
                // (`DoseScheduler.markGiven` через `quantity(at:)`).
                // Полтаблетки дважды в день — это одна таблетка в сутки,
                // а не две; до появления этого ввода счёт всегда считал
                // по две.
                TGExplainer(text: "Полтаблетки утром и целая вечером — обычное назначение. От этих чисел считается запас: приложение вычитает ровно столько, сколько дали.")
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

            // Окно «после еды» — ОТДЕЛЬНОЙ карточкой, а не третьей
            // строкой рядом с натощак: у них противоположный смысл.
            // Натощак запирает ЕДУ вокруг дозы, «после еды» запирает
            // ДОЗУ до еды (`DoseGate.state`). В одной карточке два
            // шаговика с одинаковой подписью «мин» читались бы как одно
            // правило.
            TGCard {
                Stepper(value: $послеЕдыМинут, in: 0...120, step: 5) {
                    HStack {
                        Text("Давать после еды").textStyle(AppFont.body)
                        Spacer()
                        Text(послеЕдыМинут == 0 ? "не нужно" : "\(послеЕдыМинут) мин")
                            .textStyle(AppFont.numeric(Token.FontSize.meta))
                    }
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Доза откроется через столько минут после отметки еды. Не поела — не откроется вовсе: это вопрос к врачу, а не сбой.")
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

            // Писатели для `courseEnd`, `expiry`, `openedAt`
            // и `shelfAfterOpenDays` — четырёх полей, у которых
            // человеческого писателя не было ни одного (замер
            // 26.10.2026; писали прогрев CloudKit, засев и откат архива).
            //
            // **`courseEnd` из этих четырёх дороже остальных: показ
            // у него готов и ждал только ввода.** `PillSupply
            // .shortfallDays` считает нехватку на курс, `courseEndsFirst`
            // решает, что сказать человеку, и оба читает экран
            // «Здоровье» (`:331`, `:343`) и шторка запаса (`:40`).
            // В самой модели это записано с 05.10.2026: «строка „курс
            // идёт до такого-то, не хватит столько-то" не показывалась
            // никому ни разу». Через три недели она всё ещё
            // не показывалась — не хватало ровно этих двух строк ввода.
            //
            // > **Механизм без входа не «почти работает» — он
            // > не работает**, и отличить его от рабочего нельзя
            // > ни тестом, ни компилятором: тесты передают дату
            // > аргументом сами.
            //
            // Про `remindBeforeExpiry` здесь НЕТ переключателя,
            // и это решение с доводом, а не пропуск. Разбор — в докладе
            // и ниже у `save()`.
            TGCard {
                TGSectionHeader(title: "сроки")

                Toggle(isOn: $началоНазвано) {
                    Text("Знаю, с какого дня даём").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if началоНазвано {
                    DatePicker("Начало схемы", selection: $началоСхемы,
                               in: ...Date(), displayedComponents: .date)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                    TGExplainer(text: "Начали раньше, чем завели здесь, — поставь настоящий день. От него считаются контрольные анализы.")

                    Text("Анализ крови через").textStyle(AppFont.body)
                    TGChipGroup(items: Self.неделиКонтроля,
                                title: { String(localized: "\($0) нед") },
                                isSelected: { контрольНедели.contains($0) },
                                minimumWidth: 64) { неделя in
                        if контрольНедели.contains(неделя) {
                            контрольНедели.remove(неделя)
                        } else {
                            контрольНедели.insert(неделя)
                        }
                    }
                    if !контрольНедели.isEmpty {
                        TGExplainer(text: .готовая(String(localized: "Каждая станет делом в «Прививках» на свой день: \(Self.даты(контрольНедели, от: началоСхемы)). Напомнит утренней сводкой и встанет в план дня.")))
                    }
                }

                Toggle(isOn: $естьКурсДо) {
                    Text("Курс идёт до определённого числа").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if естьКурсДо {
                    DatePicker("Курс до", selection: $курсДо, displayedComponents: .date)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                }
                TGExplainer(text: "Зная последний день, приложение скажет заранее, что таблеток до конца курса не хватит.")

                TGDivider()
                Toggle(isOn: $естьСрокГодности) {
                    Text("Срок годности указан").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if естьСрокГодности {
                    // День в сроке годности лекарств не печатают —
                    // на упаковке месяц и год. Храним конец месяца
                    // (`save()`), а спрашиваем датой: отдельного
                    // выбора «месяц и год» в SwiftUI нет, а свой
                    // здесь был бы третьим способом вводить дату
                    // в одной форме.
                    DatePicker("Годен до", selection: $срокГодности, displayedComponents: .date)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                }

                TGDivider()
                Toggle(isOn: $вскрыт) {
                    Text("Флакон вскрыт").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if вскрыт {
                    DatePicker("Когда вскрыли", selection: $когдаВскрыли, displayedComponents: .date)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                    Stepper(value: $годенПослеВскрытияДней, in: 0...365, step: 1) {
                        HStack {
                            Text("Годен после вскрытия").textStyle(AppFont.body)
                            Spacer()
                            Text(годенПослеВскрытияДней == 0
                                 ? String(localized: "не указан")
                                 : Fmt.days(годенПослеВскрытияДней))
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                // Правило словами, а не вторым вычислением: минимум
                // из двух сроков считает `Medication.goodUntil()`,
                // и повторять его здесь значило бы завести вторую
                // копию — а две копии расходятся молча. Человеку
                // нужно знать правило, чтобы понимать, почему
                // приложение потом назовёт именно эту дату.
                TGExplainer(text: "Из двух сроков действует ближний: вскрытый флакон портится раньше, чем кончается срок на упаковке.")
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
                // Надгробие, а не `context.delete`: до 26.10.2026 удаление
                // схемы до второго человека не доезжало вовсе — у мамы
                // курс оставался жив, и она получала напоминания о дозах
                // по лечению, которого больше нет. Разбор —
                // `Medication.deletedAt`.
                if let medication {
                    let откат = ОбщееУдаление.удалить(medication)
                    guard context.persist(otherwise: откат) else {
                        Haptics.warning()
                        appState.showFailure("Не удалилось · нажми ещё раз")
                        return
                    }
                }
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
        // `schedule`, а НЕ `doseSlotsData`: это и есть тот читатель,
        // которого модель завела отвечать за обе формы расписания —
        // пустые слоты он разворачивает в часы с количеством 1,
        // непустые отдаёт как есть. Читать `doseSlotsData` напрямую
        // модель запрещает своим же комментарием, и правильно:
        // у схемы, заведённой до появления слотов, там пусто,
        // а расписание у неё есть.
        слоты = medication.schedule.isEmpty
            ? [DoseSlot(minuteOfDay: 7 * 60, quantity: 1)]
            : medication.schedule
        единица = medication.unit
        номерНазначения = medication.prescriptionNumber ?? ""
        // Три «указан ли» читаются из `nil`, а не из значения: иначе
        // форма не смогла бы отличить «не введено» от даты, которую
        // `DatePicker` подставит сам, и первое же открытие формы
        // записало бы сегодняшнее число как срок годности.
        // Схема до V8 даты начала не знает: «не названо», и форма
        // не подставляет сегодняшнее число сама. Подсказка в поле —
        // первая доза журнала, но записана она будет, только если
        // человек включит переключатель.
        началоНазвано = medication.startedAt != nil
        началоСхемы = medication.startedAt
            ?? medication.doses.map(\.scheduledAt).min()
            ?? Date()
        естьКурсДо = medication.courseEnd != nil
        курсДо = medication.courseEnd ?? Date()
        естьСрокГодности = medication.expiry != nil
        срокГодности = medication.expiry ?? Date()
        вскрыт = medication.openedAt != nil
        когдаВскрыли = medication.openedAt ?? Date()
        годенПослеВскрытияДней = medication.shelfAfterOpenDays
        fastingMinutes = medication.fastingMinutes
        // У схемы, заведённой до появления поля, окно «до» читается
        // симметрично — показываем то же, что и применяем.
        fastingBeforeMinutes = medication.fastingBefore
        послеЕдыМинут = medication.minutesAfterMeal
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

    /// Один приём в расписании: час, минуты и сколько давать.
    ///
    /// Вынесено из `body` функцией, а не оставлено вложенным: с четырьмя
    /// `Picker` и `Stepper` внутри одного выражения компилятор выводит
    /// тип всей цепочки разом, и в этом проекте такая склейка уже
    /// стоила трёх секунд типизации (разбор — `ReminderScheduler
    /// .briefLines`). Явная граница снимает перебор целиком.
    @ViewBuilder
    private func слотРяд(_ index: Int) -> some View {
        HStack {
            Picker("Час", selection: Binding(
                get: { слоты[index].minuteOfDay / 60 },
                set: { слоты[index].minuteOfDay = $0 * 60 + слоты[index].minuteOfDay % 60 }
            )) {
                ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Минуты", selection: Binding(
                get: { слоты[index].minuteOfDay % 60 },
                set: { слоты[index].minuteOfDay = (слоты[index].minuteOfDay / 60) * 60 + $0 }
            )) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.menu)
            Spacer()
            if слоты.count > 1 {
                Button {
                    слоты.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Token.Status.overdueText)
                }
                .accessibilityLabel("Убрать время")
            }
        }
        .frame(minHeight: Token.Size.tapTarget)

        Stepper(value: Binding(
            get: { слоты[index].quantity },
            set: { слоты[index].quantity = $0 }
        ), in: шагКоличества...20, step: шагКоличества) {
            HStack {
                Text("Сколько давать").textStyle(AppFont.body)
                Spacer()
                Text(verbatim: "\(Fmt.decimal(слоты[index].quantity)) \(единица.shortName)")
                    .textStyle(AppFont.numeric(15))
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    /// Шаг количества: таблетку делят пополам, миллилитр — мера сам
    /// по себе.
    ///
    /// Правило берётся у `MedUnit.allowsHalves`, а не пишется здесь
    /// заново: оно уже записано в модели вместе с причиной.
    ///
    /// **Уже введённые половинки при смене единицы НЕ округляются.**
    /// Шаг решает, что предложит шаговик, и не имеет права молча менять
    /// число, которое человек ввёл с назначения: округление дозы — это
    /// другая доза, а не другое оформление.
    private var шагКоличества: Double { единица.allowsHalves ? 0.5 : 1 }

    /// Конец месяца выбранной даты.
    ///
    /// Так это записано в модели: на упаковке стоят месяц и год,
    /// и «годен до 11/2026» значит «до последнего дня ноября»,
    /// а не «до первого». Взять дату как есть значило бы укоротить
    /// срок годности на почти месяц — у лекарства это выброшенная
    /// упаковка.
    private func конецМесяца(_ дата: Date) -> Date {
        let календарь = Calendar.current
        let части = календарь.dateComponents([.year, .month], from: дата)
        guard let начало = календарь.date(from: части),
              let следующий = календарь.date(byAdding: .month, value: 1, to: начало),
              let последний = календарь.date(byAdding: .day, value: -1, to: следующий),
              let конец = календарь.date(bySettingHour: 23, minute: 59, second: 59,
                                         of: последний)
        else { return дата }
        return конец
    }

    private func save() {
        // Часы БЕЗ ПОВТОРОВ. `DayPlanBuilder` строит пункт плана с id
        // `dose-<схема>-<минута>` (`:62`), и два одинаковых часа дали бы
        // два пункта с одним id — в `ForEach` это ломается молча.
        // Количество при этом не теряется: `quantity(at:)` СКЛАДЫВАЕТ
        // слоты на один час, то есть «8:00 ½ и 8:00 ½» остаётся одной
        // таблеткой утром. Так это и описано в модели.
        let часы = Array(Set(слоты.map(\.minuteOfDay))).sorted()
        // Слоты храним только когда есть что хранить. Все количества
        // по единице — это прежняя форма расписания, за неё отвечает
        // `times`, и `Medication.schedule` разворачивает её сам. Писать
        // в `doseSlotsData` копию часов значило бы завести ВТОРОЕ место,
        // где живут часы приёма, — ровно то, от чего слот и придуман.
        let слотыВБазу = слоты.allSatisfy { $0.quantity == 1 }
            ? []
            : слоты.sorted { $0.minuteOfDay < $1.minuteOfDay }
        let target = medication ?? Medication(name: name, doseText: doseText, times: часы, fastingMinutes: fastingMinutes)
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
        let былоПослеЕды = target.minutesAfterMeal
        let былВрач = target.prescriber
        let былаМасса = target.massPerUnitMcg
        let былоНаУлице = target.canGiveOutside
        let былиСлоты = target.doseSlotsData
        let былаЕдиницаФормы = target.unitRaw
        let былНомер = target.prescriptionNumber
        let былКонецКурса = target.courseEnd
        let былоНачало = target.startedAt
        let былСрок = target.expiry
        let былоВскрытие = target.openedAt
        let былоПослеВскрытия = target.shelfAfterOpenDays

        target.name = name
        target.doseText = doseText
        target.times = часы
        target.doseSlotsData = слотыВБазу
        // Через сеттер `unit`, а не в `unitRaw` руками: перевод
        // в строку хранения записан в модели один раз, и второго
        // места ему здесь не надо.
        target.unit = единица
        // Пустая строка даёт `nil` — «не введено», а не пустой номер.
        target.prescriptionNumber = номерНазначения.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : номерНазначения.trimmingCharacters(in: .whitespaces)
        target.courseEnd = естьКурсДо ? курсДо : nil
        // Начало дня, а не момент: «с какого ДНЯ даём». Час, в который
        // человек открыл форму, утверждением о схеме не является.
        target.startedAt = началоНазвано ? Calendar.current.startOfDay(for: началоСхемы) : nil
        // Срок годности — конец месяца, разбор у `конецМесяца`.
        target.expiry = естьСрокГодности ? конецМесяца(срокГодности) : nil
        target.openedAt = вскрыт ? когдаВскрыли : nil
        // Ноль, когда флакон не вскрыт: держать дни после вскрытия
        // у невскрытого значило бы оставить половину пары, а `goodUntil`
        // читает обе — срок после вскрытия без даты вскрытия не
        // считается ничем, и поле осталось бы тихой неправдой.
        target.shelfAfterOpenDays = вскрыт ? годенПослеВскрытияДней : 0
        target.fastingMinutes = fastingMinutes
        target.fastingBeforeMinutes = fastingBeforeMinutes
        target.minutesAfterMeal = послеЕдыМинут
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
                target.doseSlotsData = былиСлоты
                target.unitRaw = былаЕдиницаФормы
                target.prescriptionNumber = былНомер
                target.courseEnd = былКонецКурса
                target.startedAt = былоНачало
                target.expiry = былСрок
                target.openedAt = былоВскрытие
                target.shelfAfterOpenDays = былоПослеВскрытия
                target.fastingMinutes = былоНатощак
                target.fastingBeforeMinutes = былоНатощакДо
                target.minutesAfterMeal = былоПослеЕды
                target.prescriber = былВрач
                target.massPerUnitMcg = былаМасса
                target.canGiveOutside = былоНаУлице
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Готово» ещё раз")
            return
        }
        // Дела контроля — ПОСЛЕ сохранения схемы и отдельным сохранением:
        // не легли они — схема при этом уже записана, и человеку
        // говорится ровно про дела, а не «не сохранилось» вообще.
        if let начало = target.startedAt, !контрольНедели.isEmpty,
           !завестиКонтроль(для: target, от: начало) {
            Haptics.warning()
            appState.showFailure("Схема сохранена, а напоминания об анализах — нет · открой и нажми ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }

    /// Недели, которые называют врачи для контроля Т4 после смены дозы:
    /// 3, 4–6, 4–8 — отсюда и набор (просьба Виктории 28.10.2026:
    /// «через 3, 4, 5, 6, 8 недель»).
    static let неделиКонтроля = [3, 4, 5, 6, 8]

    /// «18 нояб., 25 нояб.» — для подсказки под чипами.
    static func даты(_ недели: Set<Int>, от начало: Date) -> String {
        недели.sorted().compactMap {
            Calendar.current.date(byAdding: .weekOfYear, value: $0, to: начало)
        }.map(Fmt.shortDay).joined(separator: ", ")
    }

    /// Завести по делу ухода на каждую выбранную неделю.
    ///
    /// **Дело, а не своё напоминание**, и это переиспользование, а не
    /// упрощение: назначенное дело ухода уже встаёт в план дня в свой
    /// день, попадает в утреннюю сводку и отмечается «сделано». Свой
    /// канал уведомлений для анализов завёл бы второе место, где живёт
    /// «что сегодня надо сделать», — и они разошлись бы.
    ///
    /// Повторное сохранение формы дублей не плодит: дело с тем же
    /// заголовком на тот же день уже есть — второе не заводится.
    private func завестиКонтроль(для схема: Medication, от начало: Date) -> Bool {
        guard let собака = схема.dog ?? dog else { return true }
        let календарь = Calendar.current
        var заведённые: [CareTask] = []
        for неделя in контрольНедели.sorted() {
            guard let день = календарь.date(byAdding: .weekOfYear, value: неделя, to: начало) else { continue }
            let заголовок = String(localized: "Анализ крови · \(неделя) нед от начала")
            let уже = собака.careTasks.contains {
                $0.title == заголовок && $0.scheduledDate.map { календарь.isDate($0, inSameDayAs: день) } == true
            }
            if уже { continue }
            let дело = CareTask(title: заголовок,
                                detail: [схема.name, схема.doseText].filter { !$0.isEmpty }.joined(separator: " · "),
                                kind: .dated, intervalDays: 0, category: .medical,
                                scheduledDate: день)
            дело.dog = собака
            context.insert(дело)
            заведённые.append(дело)
        }
        guard !заведённые.isEmpty else { return true }
        return context.persist(otherwise: {
            for дело in заведённые {
                дело.dog = nil
                context.delete(дело)
            }
        })
    }
}
