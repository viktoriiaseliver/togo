import SwiftUI
import SwiftData

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
    /// Устойчивые идентификаторы строк — параллельно `слоты`, только
    /// для экрана (04.11.2026). Было `ForEach(слоты.indices, id: \.self)`:
    /// после «Убрать время» привязка соседней строки могла позвать
    /// `слоты[index]` со старым индексом — выход за границу массива,
    /// а `Picker` переезжал на чужую строку. В сам `DoseSlot` поле
    /// не добавлено нарочно: он кодируется в `doseSlotsData` и уезжает
    /// в общий дневник — форма данных не меняется ради экрана.
    @State private var идСлотов: [UUID] = [UUID()]
    @State private var единица: MedUnit = .tab
    @State private var fastingMinutes = 0
    @State private var fastingBeforeMinutes = 0
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
                ForEach(идСлотов, id: \.self) { id in
                    слотРяд(id)
                    if id != идСлотов.last { TGDivider() }
                }
                TGButton(title: "Добавить время", variant: .secondary, size: .medium, systemImage: "plus") {
                    слоты.append(DoseSlot(minuteOfDay: 19 * 60, quantity: 1))
                    идСлотов.append(UUID())
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
        идСлотов = слоты.map { _ in UUID() }
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
    private func слотРяд(_ id: UUID) -> some View {
        // Индекс ищется в момент вызова, а не берётся из замыкания:
        // строку могли убрать, и старый индекс указывал бы мимо.
        let слот = место(id).map { слоты[$0] } ?? DoseSlot(minuteOfDay: 0, quantity: 1)
        HStack {
            Picker("Час", selection: Binding(
                get: { место(id).map { слоты[$0].minuteOfDay / 60 } ?? 0 },
                set: { час in
                    guard let i = место(id) else { return }
                    слоты[i].minuteOfDay = час * 60 + слоты[i].minuteOfDay % 60
                }
            )) {
                ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Минуты", selection: Binding(
                get: { место(id).map { слоты[$0].minuteOfDay % 60 } ?? 0 },
                set: { минуты in
                    guard let i = место(id) else { return }
                    слоты[i].minuteOfDay = (слоты[i].minuteOfDay / 60) * 60 + минуты
                }
            )) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.menu)
            Spacer()
            if слоты.count > 1 {
                Button {
                    guard let i = место(id) else { return }
                    слоты.remove(at: i)
                    идСлотов.remove(at: i)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Token.Status.overdueText)
                }
                .accessibilityLabel("Убрать время")
            }
        }
        .frame(minHeight: Token.Size.tapTarget)

        Stepper(value: Binding(
            get: { место(id).map { слоты[$0].quantity } ?? 1 },
            set: { количество in
                guard let i = место(id) else { return }
                слоты[i].quantity = количество
            }
        ), in: шагКоличества...20, step: шагКоличества) {
            HStack {
                Text("Сколько давать").textStyle(AppFont.body)
                Spacer()
                Text(verbatim: "\(Fmt.decimal(слот.quantity)) \(единица.shortName)")
                    .textStyle(AppFont.numeric(15))
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    /// Где строка `id` сейчас — или `nil`, если её уже убрали.
    private func место(_ id: UUID) -> Int? {
        guard let i = идСлотов.firstIndex(of: id), слоты.indices.contains(i) else { return nil }
        return i
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
