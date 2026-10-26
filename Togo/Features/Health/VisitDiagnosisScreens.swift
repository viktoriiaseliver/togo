import SwiftUI
import SwiftData

// MARK: - Почему здесь шторка, а у анализа три шага

/// Визиты и диагнозы вводятся **одной шторкой**, и это не упрощение.
///
/// Трёхшаговый ход у анализа заведён против одной конкретной беды:
/// бланк несёт десяток показателей с общими датой, лабораторией
/// и номером, и в шторке человек перенабирал бы **ключ группировки**
/// десять раз. Опечатка в номере на седьмой строке разорвала бы бланк
/// на две группы, и он не понял бы почему.
///
/// У визита и диагноза общего ключа нет: одна запись на форму,
/// перенабирать нечего.
///
/// > **Ход, перенесённый туда, где его довод не действует, становится
/// > обрядом.** Три шага ради трёх шагов — это четыре лишних касания
/// > на каждый визит.
///
/// Макет это подтверждает с другой стороны: назначение в `8.2` нарисовано
/// одной формой («Назначение · форма»), а не шагами, при четырнадцати
/// полях модели.

// MARK: - Визиты

/// Визиты к врачу списком и ввод руками.
///
/// **Замер 08.10.2026: ввода не было вовсе.** `VetVisit` создавался
/// только в отладочной галерее под `#if DEBUG` — как и остальные три
/// медицинские модели. Модель, обмен, архив есть; завести запись
/// человек не мог.
struct VetVisitsScreen: View {
    var dog: Dog?

    @Environment(AppState.self) private var appState
    @State private var вводИдёт = false
    @State private var правка: VetVisit?

    private var canEdit: Bool { appState.can(.editTreatment) }

    private var визиты: [VetVisit] {
        (dog?.vetVisits ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Визиты к врачу", отступы: false)
            // Плашка — ДО первого отказа: строки визитов выключены `.disabled(!canEdit)` (`:73`),
            // а `.disabled` молчит по устройству. Правило дизайна
            // круга 5, п. 1; разбор и причина одного типа на все
            // экраны — `ПлашкаПрава`.
            if !canEdit { ПлашкаПрава(право: .editTreatment) }
            if визиты.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Визитов пока нет",
                    message: "Запиши осмотр или консультацию — дата, врач и заключение. Они войдут в отчёт врачу и останутся, даже когда курс закончится.",
                    actionTitle: canEdit ? "Добавить визит" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
                TGCard(spacing: 0) {
                    ForEach(Array(визиты.enumerated()), id: \.element.id) { индекс, визит in
                        if индекс > 0 { TGDivider() }
                        Button { if canEdit { правка = визит } } label: {
                            TGListRow(
                                title: .готовая(строкаВизита(визит)),
                                value: .готовая(Fmt.shortDay(визит.date)),
                                // Онлайн и очный визит различаются ЗНАЧКОМ,
                                // а не только словом: решение аудита
                                // компонентов — `stethoscope` / `videocam`.
                                systemImage: визит.reason == .online ? "videocam" : "stethoscope",
                                accessory: canEdit ? .chevron : .none
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                }
            }
        }
        .navigationTitle("Визиты к врачу")
        .cinemaScreen()
        .toolbar {
            if canEdit, dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { вводИдёт = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить визит")
                }
            }
        }
        .sheet(isPresented: $вводИдёт) { VetVisitEditor(dog: dog) }
        .sheet(item: $правка) { визит in VetVisitEditor(visit: визит, dog: dog) }
    }

    /// Повод и врач в одной строке: повод — то, зачем шли, и без него
    /// список визитов читается как список дат.
    private func строкаВизита(_ визит: VetVisit) -> String {
        let части = [визит.reason.title, Fmt.notBlank(визит.doctor)]
        return части.compactMap { $0 }.joined(separator: " · ")
    }
}

struct VetVisitEditor: View {
    var visit: VetVisit?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var всеКлиники: [Clinic]

    /// Кто принимал — **клиники, БЕЗ лабораторий**, и это требование
    /// модели, а не вкус: `Clinic.swift:34` — «лаборатория, а не
    /// клиника: туда сдают анализы, **там не принимают**».
    ///
    /// До 26.10.2026 фильтра не было вовсе: пикер перечислял
    /// `ForEach(клиники)` подряд, и в списке «кто принимал» стояли
    /// IDEXX и Antech — организации, которые приём не ведут
    /// по устройству. Поле `isLab` объяснено в модели на шести строках
    /// и не читалось ни одним экраном.
    ///
    /// **Выбранная клиника остаётся в списке всегда, даже если она
    /// лаборатория или уже надгробие.** Без этого правка старого визита
    /// молча теряла бы организацию: пикер показал бы «не указана»
    /// при заполненном `visit.clinic`, человек сохранил бы форму,
    /// не трогая это поле, и `цель.clinic = клиника` записало бы `nil`.
    /// То есть фильтр показа стал бы **молчаливым удалением данных** —
    /// ровно тот класс, что «вид выводится из заполненности».
    private var доступные: [Clinic] {
        let живые = всеКлиники.filter { $0.deletedAt == nil && !$0.isLab }
        let выбранная = клиника.map { [$0] } ?? []
        let слитые = живые + выбранная.filter { выбор in
            !живые.contains { $0.persistentModelID == выбор.persistentModelID }
        }
        return слитые.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @State private var дата = Date()
    @State private var повод: VisitReason = .checkup
    @State private var врач = ""
    @State private var заключение = ""
    @State private var клиника: Clinic?
    @State private var загружено = false
    @State private var удаляем = false

    private var новый: Bool { visit == nil }

    var body: some View {
        TGSheet(title: новый ? "Новый визит" : "Визит",
                subtitle: "дата, повод и заключение — то, что спросят в следующий раз",
                closeTitle: новый ? "Отмена" : "Закрыть",
                hasUnsavedChanges: новый && !(врач + заключение).trimmingCharacters(in: .whitespaces).isEmpty) {
            TGCard {
                // Повод — сегментом: четыре значения, и все четыре
                // человек выбирает, а не печатает.
                Picker("Повод", selection: $повод) {
                    ForEach(VisitReason.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TGExplainer(text: "Онлайн-консультация — такой же визит: он тоже попадает в отчёт врачу.")
            }

            TGCard(spacing: 0) {
                DatePicker("Дата", selection: $дата, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                LabeledField(label: "Врач") {
                    // Была фамилия живого врача. `TextField(_ titleKey:)` —
                    // `LocalizedStringKey`, и она уехала переводчику:
                    // в каталоге лежали `en Kochubina`, `fr Kotchoubina`,
                    // `uk Кочубіна`. Разбор — `ПодсказкаНеДанныеTests`.
                    TextField("фамилия врача", text: $врач)
                }
                TGDivider()
                // Клиника выбирается из уже заведённых, а не печатается:
                // справочник склеивается по имени, и свободный ввод
                // плодил бы «Vet Riviera» и «вет ривьера» как две разные.
                //
                // **Довод был верен, а справочника не существовало
                // до 26.10.2026** — у человека здесь навсегда стояла
                // одна строка «не указана». Вход теперь есть:
                // «Здоровье» → «Клиники и лаборатории».
                Picker("Клиника", selection: $клиника) {
                    Text("не указана").tag(nil as Clinic?)
                    ForEach(доступные) { Text(verbatim: $0.name).tag($0 as Clinic?) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Token.Size.tapTarget)
                // Пустой справочник больше не молчит. Прежде пикер
                // с одной строкой «не указана» выглядел поломкой
                // экрана; теперь он говорит, где завести организацию.
                if доступные.isEmpty {
                    TGExplainer(text: "Справочник пуст. Клиники заводятся в «Здоровье» → «Клиники и лаборатории» — оттуда они и попадают в этот выбор.")
                }
                // Телефон выбранной клиники — нажимаемым и ЗДЕСЬ,
                // а не только в справочнике: визит заводят, когда
                // из клиники вернулись или когда в неё собираются,
                // и это второй из двух часов, когда номер нужен.
                if let номер = Fmt.notBlank(клиника?.phone ?? "") {
                    TGDivider()
                    СтрокаЗвонка(номер: номер)
                }
            }

            TGCard {
                TGSectionHeader(title: "заключение")
                TextField("что сказал врач", text: $заключение, axis: .vertical)
                    .textStyle(AppFont.body)
                    .frame(minHeight: Token.Size.tapTarget)
            }

            if visit != nil {
                TGButton(title: "Удалить визит", variant: .destructive, size: .medium, systemImage: "trash") {
                    удаляем = true
                }
            }
        } footer: {
            TGButton(title: новый ? "Добавить" : "Сохранить") { сохранить() }
        }
        .presentationDetents([.large])
        .task { загрузить() }
        .confirmationDialog("Удалить визит?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                // Надгробие вместо `context.delete` — см. `Medication.deletedAt`.
                if let visit {
                    let откат = ОбщееУдаление.удалить(visit)
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
            Text("Визит уйдёт из истории и из отчёта врачу. Диагнозы и назначения останутся.")
        }
    }

    private func загрузить() {
        guard !загружено, let visit else { загружено = true; return }
        дата = visit.date
        повод = visit.reason
        врач = visit.doctor
        заключение = visit.conclusion
        клиника = visit.clinic
        загружено = true
    }

    private func сохранить() {
        let цель = visit ?? VetVisit(date: дата)
        let былаДата = цель.date
        let былПовод = цель.reasonRaw
        let былВрач = цель.doctor
        let былоЗаключение = цель.conclusion
        let былаКлиника = цель.clinic
        let былоИзменено = цель.changedAt

        цель.date = дата
        цель.reason = повод
        цель.doctor = врач.trimmingCharacters(in: .whitespaces)
        цель.conclusion = заключение
        цель.clinic = клиника
        цель.changedAt = Date()

        let новое = visit == nil
        if новое {
            цель.dog = dog
            context.insert(цель)
        }

        guard context.persist(otherwise: {
            if новое {
                цель.dog = nil
                context.delete(цель)
            } else {
                цель.date = былаДата
                цель.reasonRaw = былПовод
                цель.doctor = былВрач
                цель.conclusion = былоЗаключение
                цель.clinic = былаКлиника
                цель.changedAt = былоИзменено
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Диагнозы

/// Диагнозы списком и ввод руками.
///
/// **Статус показывается словом И формой значка, а не цветом** —
/// требование аудита компонентов (`DiagnosisRow`: «три статуса —
/// словом и формой значка»). У нас это записано шире: срочность
/// и состояние никогда не передаются одним цветом, потому что глиф
/// для речи — то же, что цвет для зрения, и починка в одной
/// модальности из двух выглядит законченной.
struct DiagnosesScreen: View {
    var dog: Dog?

    @Environment(AppState.self) private var appState
    @State private var вводИдёт = false
    @State private var правка: Diagnosis?

    private var canEdit: Bool { appState.can(.editTreatment) }

    /// Снятые — вниз: они факт истории, а не текущее состояние.
    /// Но НЕ скрыты: «ничего не удаляется» — красная линия, и снятый
    /// диагноз объясняет, почему лечили именно так.
    private var диагнозы: [Diagnosis] {
        (dog?.diagnoses ?? []).sorted { левый, правый in
            if (левый.status == .withdrawn) != (правый.status == .withdrawn) {
                return правый.status == .withdrawn
            }
            return левый.madeOn > правый.madeOn
        }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Диагнозы", отступы: false)
            // Плашка — ДО первого отказа: строки диагнозов выключены `.disabled(!canEdit)` (`:332`),
            // а `.disabled` молчит по устройству. Правило дизайна
            // круга 5, п. 1; разбор и причина одного типа на все
            // экраны — `ПлашкаПрава`.
            if !canEdit { ПлашкаПрава(право: .editTreatment) }
            if диагнозы.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Диагнозов пока нет",
                    message: "Запиши, что предполагает врач и на чём это основано. Рабочая гипотеза — тоже запись: по ней видно, почему лечение именно такое.",
                    actionTitle: canEdit ? "Добавить диагноз" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
                TGCard(spacing: 0) {
                    ForEach(Array(диагнозы.enumerated()), id: \.element.id) { индекс, диагноз in
                        if индекс > 0 { TGDivider() }
                        Button { if canEdit { правка = диагноз } } label: {
                            TGListRow(
                                // **Третья редакция этой строки, и первые две
                                // измерены кадром.** У `TGListRow` два
                                // текстовых слота, а показать надо три вещи:
                                // формулировку, статус и дату. Три в два
                                // не влезают, и `ViewThatFits` при нехватке
                                // ширины роняет значение под заголовок —
                                // нарочно, чтобы не ужимать текст.
                                //
                                //   статус в значении ПОЛНЫМ словом
                                //       2 строки из 3 держали колонку
                                //   формулировка + статус в заголовке, дата справа
                                //       1 из 3 — вниз поехала ДАТА,
                                //       а она и есть то устойчивое,
                                //       ради чего колонку освобождали
                                //   статус КОРОТКИМ словом, даты в строке нет
                                //       ← эта редакция: значение самое короткое
                                //
                                // > **Освободив колонку значения, я заполнил
                                // > заголовок так, что значение вытеснилось
                                // > снова.** Правило «в значении только
                                // > короткое и устойчивое» я исполнил
                                // > наполовину: убрал переменное и не заметил,
                                // > что сам кладу рядом ещё больше текста.
                                //
                                // Дата из строки убрана СОЗНАТЕЛЬНО: она есть
                                // в форме правки, список отсортирован (снятые
                                // вниз, внутри — по дате), а статус словом
                                // убрать нельзя — значки по силуэту
                                // неразличимы, замер 625/584/575, разброс 8 %.
                                // Из трёх полей жертвуем тем, у которого есть
                                // второй адрес.
                                //
                                // Это продуктовое решение, а не вынужденное:
                                // оно обратимо, и у него есть альтернатива —
                                // завести строке третий слот (подзаголовок)
                                // в `TGListRow`. Это правка общего компонента
                                // на весь проект, и она не моя.
                                title: .готовая(Fmt.notBlank(диагноз.wording) ?? String(localized: "без формулировки")),
                                value: .готовая(диагноз.status.shortTitle),
                                systemImage: значок(диагноз.status),
                                accessory: canEdit ? .chevron : .none
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                }

                TGCard {
                    TGExplainer(text: "Снятый диагноз остаётся в списке и в отчёте: он объясняет, почему лечили именно так.")
                }
            }
        }
        .navigationTitle("Диагнозы")
        .cinemaScreen()
        .toolbar {
            if canEdit, dog != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { вводИдёт = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить диагноз")
                }
            }
        }
        .sheet(isPresented: $вводИдёт) { DiagnosisEditor(dog: dog) }
        .sheet(item: $правка) { диагноз in DiagnosisEditor(diagnosis: диагноз, dog: dog) }
    }

    /// Значок статуса.
    ///
    /// **ЗАМЕРЕНО 08.10.2026, и замер против меня: по силуэту эти три
    /// значка НЕРАЗЛИЧИМЫ.** Счёт тёмных пикселей в прямоугольнике
    /// значка на кадрах:
    ///
    /// ```
    /// checkmark.seal        625
    /// questionmark.circle   584
    /// slash.circle          575      разброс 8 %
    /// ```
    ///
    /// У двух из трёх внешний контур — буквально один и тот же круг,
    /// различает только внутренний глиф. На беглом взгляде в списке
    /// это «кружок с чем-то внутри» трижды.
    ///
    /// **И правка здесь НЕ делается — сознательно.** Статус назван
    /// СЛОВОМ в каждой строке, значок не единственный носитель,
    /// и правило «ни цветом, ни значком, ни положением — словом»
    /// соблюдено.
    ///
    /// > **Опасность не в значках, а в том дне, когда кто-нибудь
    /// > уберёт слово ради краткости.** Тогда значки не удержат,
    /// > и выяснится это не сразу: три одинаковых кружка читаются
    /// > как «статус показан».
    ///
    /// Поэтому слово сторожится прогоном: `МедслойДороги`
    /// (`testДорогаКДиагнозамСнята`) требует все три статуса словами
    /// в списке и падает, если слово исчезло. Снявший слово узнает
    /// об этом от сторожа, а не от человека через месяц.
    private func значок(_ статус: DiagnosisStatus) -> String {
        switch статус {
        case .hypothesis: "questionmark.circle"
        case .confirmed: "checkmark.seal"
        case .withdrawn: "slash.circle"
        }
    }
}

struct DiagnosisEditor: View {
    var diagnosis: Diagnosis?
    var dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var формулировка = ""
    @State private var статус: DiagnosisStatus = .hypothesis
    @State private var когда = Date()
    @State private var кем = ""
    @State private var основание = ""
    @State private var загружено = false
    @State private var удаляем = false

    private var новый: Bool { diagnosis == nil }
    private var можноСохранить: Bool {
        !формулировка.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        TGSheet(title: новый ? "Новый диагноз" : .готовая(формулировка),
                subtitle: "формулировка, статус и на чём основано",
                closeTitle: новый ? "Отмена" : "Закрыть",
                hasUnsavedChanges: новый && можноСохранить) {
            TGCard {
                // `shortTitle`, а НЕ `title`: кадр 08.10.2026, снятый
                // не автором, показал «рабочая гипо…» — обрезку
                // многоточием на СТАНДАРТНОМ кегле и на iPhone 17 Pro.
                // Ни крупного шрифта, ни узкого экрана не потребовалось.
                //
                // > **Обрезанное слово в органе управления хуже,
                // > чем в показе: по показу читают, а по органу выбирают.**
                //
                // В списке и в отчёте остаётся полное `title`: там место
                // есть, а «рабочая» отличает предположение от вывода.
                Picker("Статус", selection: $статус) {
                    ForEach(DiagnosisStatus.allCases, id: \.self) { Text(verbatim: $0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                TGExplainer(text: "Рабочая гипотеза — полноценная запись. Снять её потом можно, стереть — нет: по ней видно, почему лечение было таким.")
            }

            TGCard(spacing: 0) {
                LabeledField(label: "Формулировка") {
                    TextField("гипотиреоз", text: $формулировка)
                }
                TGDivider()
                DatePicker("Когда поставлен", selection: $когда, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                LabeledField(label: "Кем") {
                    TextField("врач или клиника", text: $кем)
                }
            }

            TGCard {
                TGSectionHeader(title: "на чём основано")
                TextField("анализы, осмотр, симптомы", text: $основание, axis: .vertical)
                    .textStyle(AppFont.body)
                    .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Это поле отвечает на вопрос «почему так решили» через полгода, когда никто не помнит.")
            }

            if diagnosis != nil {
                TGButton(title: "Удалить диагноз", variant: .destructive, size: .medium, systemImage: "trash") {
                    удаляем = true
                }
            }
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Форма — по образцу запаса корма (`d569d01`):
            // строка над кнопкой, на ТОЙ ЖЕ величине, что ворота.
            VStack(spacing: Token.Space.s8) {
                if !можноСохранить {
                    Text("Напиши формулировку — хотя бы рабочую гипотезу")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: новый ? "Добавить" : "Сохранить", isEnabled: можноСохранить) { сохранить() }
            }
        }
        .presentationDetents([.large])
        .task { загрузить() }
        .confirmationDialog("Удалить диагноз?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                // Надгробие вместо `context.delete`. Удалённый диагноз
                // и СНЯТЫЙ — разные вещи: снятый остаётся в карте
                // и объясняет, что искали.
                if let diagnosis {
                    let откат = ОбщееУдаление.удалить(diagnosis)
                    guard context.persist(otherwise: откат) else {
                        Haptics.warning()
                        appState.showFailure("Не удалилось · нажми ещё раз")
                        return
                    }
                }
                Haptics.warning()
                dismiss()
            }
            Button("Снять диагноз") {
                diagnosis?.status = .withdrawn
                diagnosis?.changedAt = Date()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Удаление уберёт запись из отчёта врачу. «Снять диагноз» оставит её в истории — обычно нужно именно это.")
        }
    }

    private func загрузить() {
        guard !загружено, let diagnosis else { загружено = true; return }
        формулировка = diagnosis.wording
        статус = diagnosis.status
        когда = diagnosis.madeOn
        кем = diagnosis.madeBy
        основание = diagnosis.evidence
        загружено = true
    }

    private func сохранить() {
        let цель = diagnosis ?? Diagnosis(wording: формулировка, madeOn: когда)
        let былаФормулировка = цель.wording
        let былСтатус = цель.statusRaw
        let былаДата = цель.madeOn
        let былКем = цель.madeBy
        let былоОснование = цель.evidence
        let былоИзменено = цель.changedAt

        цель.wording = формулировка.trimmingCharacters(in: .whitespaces)
        цель.status = статус
        цель.madeOn = когда
        цель.madeBy = кем.trimmingCharacters(in: .whitespaces)
        цель.evidence = основание
        цель.changedAt = Date()

        let новое = diagnosis == nil
        if новое {
            цель.dog = dog
            context.insert(цель)
        }

        guard context.persist(otherwise: {
            if новое {
                цель.dog = nil
                context.delete(цель)
            } else {
                цель.wording = былаФормулировка
                цель.statusRaw = былСтатус
                цель.madeOn = былаДата
                цель.madeBy = былКем
                цель.evidence = былоОснование
                цель.changedAt = былоИзменено
            }
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
