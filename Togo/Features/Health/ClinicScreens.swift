import SwiftUI
import SwiftData

// MARK: - Справочник клиник и лабораторий

/// Справочник клиник и лабораторий — **первый и единственный вход
/// в `Clinic` для человека**.
///
/// # Чем это оплачено. Замер 26.10.2026
///
/// У `Clinic` не было ни одного человеческого места создания. Все
/// четыре, что есть в коде, человеку недостижимы по устройству:
///
/// ```
/// SharedDiaryPayloads.swift:797   приём ИЗВНЕ — клиника приезжает
///                                 от второго телефона, своей не завести
/// Backup.swift:395                откат архива — только то, что уже было
/// CloudKitSchemaWarmup.swift:234  маркер схемы, служебная запись
/// MedicalRecordGallery.swift:93   целиком под `#if DEBUG`
/// ```
///
/// И при этом **два экрана её уже спрашивали**:
/// `VetVisitEditor` и `PrescriptionEditor` рисуют `Picker("Клиника")`
/// поверх `@Query [Clinic]`. У человека там навсегда стояла одна
/// строка — «не указана», — и выбрать было нечего и никогда.
///
/// > **Это хуже мёртвого поля: экран спрашивал то, на что ответить
/// > нельзя.** И выглядело это не поломкой, а его собственной
/// > невнимательностью — «почему у меня список пустой».
///
/// # Почему справочник, а не свободный ввод
///
/// Довод не наш и записан в двух местах: `Clinic.swift:6-13`
/// («человек наберёт „Vet Riviera“ двенадцать раз по-разному,
/// и группировка сломается») и `VisitDiagnosisScreens.swift:151-153`
/// («справочник склеивается по имени»). Довод верный — не было
/// справочника.
///
/// **То есть автор отказался от свободного ввода правильно и не завёл
/// замену.** Решение было верным, а работа — половинной, и половина
/// без второй половины неотличима от недоделки.
///
/// # Собаки у этого экрана нет, и это не упущение
///
/// Остальные двенадцать строк `sectionsGrid` принимают `dog:`.
/// `Clinic` **не принадлежит собаке** — ни связи `dog`, ни обратной
/// у `Dog` (`Clinic.swift`: три связи, все к `CareTask`, `VetVisit`
/// и `Prescription`). Клиника одна на всех собак семьи, и приведи
/// мы её к собаке — у второй собаки справочник оказался бы пуст
/// при тех же одиннадцати организациях.
struct ClinicsScreen: View {
    @Environment(AppState.self) private var appState
    /// Все клиники, включая надгробия: фильтр стоит ниже, в `живые`.
    /// Отбор в `@Query` не делается нарочно — предикат
    /// `#Predicate { $0.deletedAt == nil }` пришлось бы повторить
    /// в трёх местах этого файла, а правило «две копии разойдутся
    /// молча» здесь уже оплачено трижды.
    @Query private var всеКлиники: [Clinic]

    @State private var вводИдёт = false
    @State private var правка: Clinic?

    /// Справочник правит тот, кто правит лечение: из него выбирают
    /// на визите, в назначении и у анализа, и все три гасятся
    /// `editTreatment`. Второе право на тот же предмет развело бы
    /// одно решение двумя хозяевами.
    private var canEdit: Bool { appState.can(.editTreatment) }

    /// **Надгробия отфильтрованы, и это не стиль.** `ОбщееУдаление`
    /// говорит об этом прямо: «надгробие, которое видно человеку, —
    /// не удаление, а порча экрана». Клиника, удалённая на втором
    /// телефоне, обязана исчезнуть и здесь, и из обоих пикеров.
    private var живые: [Clinic] {
        всеКлиники.filter { $0.deletedAt == nil }
    }

    /// Разложены по тому самому признаку, ради которого `isLab`
    /// и заведён. Сортировка по имени: справочник читают глазами,
    /// а порядок вставки человеку ничего не говорит.
    private var лаборатории: [Clinic] {
        живые.filter(\.isLab).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var клиники: [Clinic] {
        живые.filter { !$0.isLab }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Клиники и лаборатории", надпись: "справочник", отступы: false)
            // Плашка — ДО первого отказа: строки справочника выключены
            // `.disabled(!canEdit)`, а `.disabled` молчит по устройству.
            // Разбор и причина одного типа на все экраны — `ПлашкаПрава`.
            if !canEdit { ПлашкаПрава(право: .editTreatment) }

            if живые.isEmpty {
                EmptyStateCard(
                    subject: .health,
                    title: "Клиник пока нет",
                    message: "Заведи клинику или лабораторию: название, телефон и чем она отличается от соседней. После этого они появятся в выборе у визита, у назначения и у анализа.",
                    actionTitle: canEdit ? "Добавить клинику" : nil,
                    action: canEdit ? { вводИдёт = true } : nil
                )
            } else {
                if !клиники.isEmpty {
                    TGSectionHeader(title: "клиники")
                    список(клиники)
                }
                if !лаборатории.isEmpty {
                    TGSectionHeader(title: "лаборатории")
                    список(лаборатории)
                }
                TGCard {
                    TGExplainer(text: "Один раз заведённую клинику дальше только выбирают — так записи о ней собираются в одну группу, а не в двенадцать с опечатками.")
                }
            }
        }
        .navigationTitle("Клиники и лаборатории")
        .cinemaScreen()
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { вводИдёт = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить клинику")
                }
            }
        }
        .sheet(isPresented: $вводИдёт) { ClinicEditor() }
        .sheet(item: $правка) { клиника in ClinicEditor(clinic: клиника) }
    }

    /// Строка справочника: название, пояснение значением, телефон —
    /// **отдельной нажимаемой строкой под ней**.
    ///
    /// Телефон не прячется в форму правки, и причина измерена не нами:
    /// `SharedDiarySyncTests.swift:403` держит его обменом со словами
    /// «название клиники без номера не помогает в тот час, когда…».
    /// Тот час — это когда собаке плохо; открывать ради номера форму
    /// правки, листать её и не нажать на номер, потому что он лежит
    /// в текстовом поле, — это и есть «не помогает».
    @ViewBuilder
    private func список(_ организации: [Clinic]) -> some View {
        TGCard(spacing: 0) {
            ForEach(Array(организации.enumerated()), id: \.element.id) { индекс, клиника in
                if индекс > 0 { TGDivider() }
                Button { if canEdit { правка = клиника } } label: {
                    TGListRow(
                        title: .готовая(Fmt.notBlank(клиника.name) ?? String(localized: "без названия")),
                        value: Fmt.notBlank(клиника.detail ?? "").map { .готовая($0) },
                        systemImage: клиника.isLab ? "testtube.2" : "cross.case",
                        accessory: canEdit ? .chevron : .none
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)

                // Звонок открыт ВСЕМ, кто видит медицинское, а не только
                // правящему схему: звонить в клинику — не правка
                // справочника. Гость с собакой на руках должен дозвониться.
                if let номер = Fmt.notBlank(клиника.phone ?? "") {
                    СтрокаЗвонка(номер: номер)
                }
            }
        }
    }
}

/// Нажимаемый телефон одной строкой.
///
/// Вынесено, потому что зовётся из трёх мест — справочника, визита
/// и назначения, — а «две копии разойдутся молча» в этом проекте
/// оплачено отдельной строкой свода. Здесь копии разошлись бы
/// на извлечении цифр, то есть на том, дозвонится человек или нет.
struct СтрокаЗвонка: View {
    let номер: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { позвонить() } label: {
            // `.готовая` на данных человека — **не мой выбор, а предел
            // компонента**: у `TGListRow.value` тип `LocalizedStringKey?`
            // и варианта на `Надпись` нет вовсе (замер 26.10.2026
            // по `TGRows.swift`). Так же вынужденно поступают все
            // соседи: `VetVisitsScreen` гонит через неё ФАМИЛИЮ ВРАЧА,
            // `PrescriptionsScreen` — номер рецепта. Вреда в показе
            // нет (промах по каталогу возвращает саму строку), а в
            // каталог номер не попадёт: извлечение берёт литералы,
            // а здесь переменная. Починка — овеществить `Надпись`
            // в `TGListRow`, и это правка общего компонента, не моя.
            TGListRow(title: "Позвонить",
                      value: .готовая(номер),
                      systemImage: "phone",
                      accessory: .none)
        }
        .buttonStyle(.plain)
    }

    /// Та же выжимка цифр, что в `EmergencyScreen:84`
    /// и `AlarmThresholdScreen:95`: `tel://` не принимает пробелы
    /// и скобки, в которых человек записывает номер с визитки.
    private func позвонить() {
        let цифры = номер.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(цифры)") else { return }
        openURL(url)
    }
}

// MARK: - Форма

/// Ввод клиники. Одна шторка: четыре поля, общего ключа группировки
/// у них нет — трёхшаговый ход анализа здесь был бы обрядом.
struct ClinicEditor: View {
    var clinic: Clinic?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var название = ""
    @State private var пояснение = ""
    @State private var лаборатория = false
    @State private var телефон = ""
    @State private var загружено = false
    @State private var удаляем = false

    private var новая: Bool { clinic == nil }

    /// **Непустое имя — не стиль, а условие работы справочника.**
    /// `Clinic.swift:25-28`: имя это ключ группировки, и «непустота
    /// проверяется при вводе, а не здесь». Здесь — это и есть «при
    /// вводе». Безымянная клиника не склеится ни с чем и даст
    /// в пикере пустую строку.
    private var можноСохранить: Bool {
        !название.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        TGSheet(title: новая ? "Новая клиника" : .готовая(Fmt.notBlank(название) ?? String(localized: "Клиника")),
                subtitle: "название и телефон — то, что понадобится в тот час, когда звонить",
                closeTitle: новая ? "Отмена" : "Закрыть",
                hasUnsavedChanges: новая && можноСохранить) {
            TGCard(spacing: 0) {
                LabeledField(label: String(localized: "Название")) {
                    // Подсказка — слово-роль, а не образец данных:
                    // «Vet Riviera» вынесло бы наружу название живой
                    // клиники и уехало бы переводчику. Разбор —
                    // `ПодсказкаНеДанныеTests`.
                    TextField("название клиники", text: $название)
                }
                TGDivider()
                LabeledField(label: String(localized: "Чем отличается")) {
                    TextField("город или адрес", text: $пояснение)
                }
                TGExplainer(text: "Пояснение нужно, когда у двух организаций одно название: в выборе иначе две одинаковые строки.")
            }

            TGCard(spacing: 0) {
                LabeledField(label: String(localized: "Телефон")) {
                    TextField("номер телефона", text: $телефон)
                        .keyboardType(.phonePad)
                }
                TGExplainer(text: "Номер открывается нажатием прямо из справочника — искать его в форме правки в тот час некогда.")
            }

            TGCard {
                Toggle(isOn: $лаборатория) {
                    Text("Это лаборатория").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Анализы сдают в лабораторию, принимают — в клинике. Переключатель решает, в каком из двух списков она появится и где её предложат выбрать.")
            }

            if clinic != nil {
                TGButton(title: "Удалить клинику", variant: .destructive, size: .medium, systemImage: "trash") {
                    удаляем = true
                }
            }
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает.
            VStack(spacing: Token.Space.s8) {
                if !можноСохранить {
                    Text("Назови клинику — по названию справочник и склеивается")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: новая ? "Добавить" : "Сохранить", isEnabled: можноСохранить) { сохранить() }
            }
        }
        .presentationDetents([.large])
        .task { загрузить() }
        .confirmationDialog("Удалить клинику?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { удалить() }
            Button("Отмена", role: .cancel) {}
        } message: {
            // Последствие названо точно, и оно не самоочевидно:
            // у `Clinic` все три связи стоят `.nullify` нарочно
            // (`Clinic.swift:60-66`) — «прививка остаётся фактом, даже
            // если организацию убрали из справочника». Человек,
            // прибирающий список, обязан знать, что историю он НЕ трёт.
            Text("Клиника уйдёт из справочника. Визиты, назначения и прививки в ней останутся: они факт того дня, даже когда организации в списке больше нет.")
        }
    }

    private func загрузить() {
        guard !загружено, let clinic else { загружено = true; return }
        название = clinic.name
        пояснение = clinic.detail ?? ""
        лаборатория = clinic.isLab
        телефон = clinic.phone ?? ""
        загружено = true
    }

    /// **Мягкое удаление, а не `context.delete`.** Жёсткое до второго
    /// человека не доезжает по устройству: удалённую запись
    /// `FamilySync.enqueueLocalChanges` не получает ни в `inserted`,
    /// ни в `updated`, собрать по ней `CKRecord` неоткуда. Разбор
    /// и пара «надгробие + `changedAt`» — `ОбщееУдаление`, и руками
    /// поля не ставятся: половина пары опаснее целой.
    private func удалить() {
        guard let clinic else { return }
        let былоУдалено = clinic.deletedAt
        let былоИзменено = clinic.changedAt
        ОбщееУдаление.удалить(clinic)
        guard context.persist(otherwise: {
            clinic.deletedAt = былоУдалено
            clinic.changedAt = былоИзменено
        }) else {
            Haptics.warning()
            appState.showFailure("Не удалилось · попробуй ещё раз")
            return
        }
        Haptics.warning()
        dismiss()
    }

    private func сохранить() {
        let цель = clinic ?? Clinic(name: название)
        let былоНазвание = цель.name
        let былоПояснение = цель.detail
        let былаЛаборатория = цель.isLab
        let былТелефон = цель.phone
        let былоИзменено = цель.changedAt

        цель.name = название.trimmingCharacters(in: .whitespaces)
        цель.detail = Fmt.notBlank(пояснение)
        цель.isLab = лаборатория
        цель.phone = Fmt.notBlank(телефон)
        // Время правки на ЭТОМ телефоне — им решается спор двух
        // телефонов при обмене (`SharedDiary.resolve(local:remote:)`).
        цель.changedAt = Date()

        let новое = clinic == nil
        if новое { context.insert(цель) }

        guard context.persist(otherwise: {
            if новое {
                context.delete(цель)
            } else {
                цель.name = былоНазвание
                цель.detail = былоПояснение
                цель.isLab = былаЛаборатория
                цель.phone = былТелефон
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
