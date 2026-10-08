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
        .posterHeader("Визиты к врачу")
        .navigationBarTitleDisplayMode(.large)
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
    @Query private var клиники: [Clinic]

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
                    TextField("Кочубина", text: $врач)
                }
                TGDivider()
                // Клиника выбирается из уже заведённых, а не печатается:
                // справочник склеивается по имени, и свободный ввод
                // плодил бы «Vet Riviera» и «вет ривьера» как две разные.
                Picker("Клиника", selection: $клиника) {
                    Text("не указана").tag(nil as Clinic?)
                    ForEach(клиники) { Text(verbatim: $0.name).tag($0 as Clinic?) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Token.Size.tapTarget)
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
                if let visit { context.delete(visit) }
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
            appState.showUndo("Не сохранилось · нажми ещё раз")
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
                                title: .готовая(Fmt.notBlank(диагноз.wording) ?? String(localized: "без формулировки")),
                                // Статус СЛОВОМ в значении строки.
                                value: .готовая(диагноз.status.title),
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
        .posterHeader("Диагнозы")
        .navigationBarTitleDisplayMode(.large)
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

    /// **Форма значка, а не цвет.** Три разных глифа, различимых
    /// по силуэту: вопрос, галочка в печати, зачёркнутый круг.
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
                Picker("Статус", selection: $статус) {
                    ForEach(DiagnosisStatus.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
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
            TGButton(title: новый ? "Добавить" : "Сохранить", isEnabled: можноСохранить) { сохранить() }
        }
        .presentationDetents([.large])
        .task { загрузить() }
        .confirmationDialog("Удалить диагноз?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let diagnosis { context.delete(diagnosis) }
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
            Text("Удаление уберёт запись из отчёта врачу. «Снять» оставит её в истории — обычно нужно именно это.")
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
            appState.showUndo("Не сохранилось · нажми ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
