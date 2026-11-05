import SwiftUI
import SwiftData

// MARK: - Правка одной строки

/// Правка ОДНОЙ существующей строки — здесь шторка верна.
///
/// Трёхшаговый ход заведён против перенабора общего бланка; у одной
/// строки общего бланка нет, и разбивать её правку на шаги значило бы
/// перенести ход туда, где его довод не действует.
struct LabResultRowEditor: View {
    let result: LabResult

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @Query private var всеКлиники: [Clinic]

    @State private var черновик = ЧерновикПоказателя()
    @State private var загружено = false
    @State private var удаляем = false

    // Поля БЛАНКА — пять штук, и до 26.10.2026 правке не поддавался
    // ни один из них.
    @State private var лаборатория = ""
    @State private var номерБланка = ""
    @State private var раздел = ""
    @State private var датаЗабора = Date()
    @State private var времяИзвестно = false
    @State private var времяЗабора = Date()

    /// Какое числовое поле в фокусе. Здесь **без** `id`, в отличие
    /// от `LabResultEntryFlow`: черновик один на весь лист, цикла нет,
    /// и три случая различают поля однозначно. Форма условия названа
    /// по тому, что есть, а не скопирована у соседа.
    private enum ПолеСтроки: Hashable { case число, нормаНиз, нормаВерх }

    @FocusState private var фокус: ПолеСтроки?

    /// Где сдавали — **и лаборатории, И клиники, без фильтра
    /// по `isLab`**. Это НЕ то же самое, что «кто принимал», и разница
    /// измерена, а не выбрана.
    ///
    /// Наряд просил «фильтр в двух пикерах по `isLab`». Для «кто
    /// принимал» это верно (лаборатория приём не ведёт), а здесь
    /// **фильтр был бы дефектом**: `LabResultScreens.swift:562` говорит
    /// прямо — «`Medical.swift:41`: „Лаборатория: IDEXX · Antech ·
    /// КЛИНИКА" — анализ часто сдают в обычной клинике». Оставь я тут
    /// только `isLab`, и человек, сдавший кровь у своего врача,
    /// не смог бы указать, где сдавал.
    ///
    /// > **Признак `isLab` несимметричен: он запрещает приём
    /// > в лаборатории и НЕ запрещает забор в клинике.** Один фильтр
    /// > на два вопроса дал бы правильный ответ одному из них.
    ///
    /// Лаборатории идут первыми — они тут частый случай, — а внутри
    /// каждой группы по имени.
    private var доступные: [Clinic] {
        всеКлиники
            .filter { $0.deletedAt == nil }
            .sorted { левая, правая in
                if левая.isLab != правая.isLab { return левая.isLab }
                return левая.name.localizedStandardCompare(правая.name) == .orderedAscending
            }
    }

    /// Значение, которого в справочнике нет. Бланки, заведённые
    /// до справочника, несут лабораторию СТРОКОЙ, и она обязана
    /// остаться выбранной: иначе правка показателя молча переписала бы
    /// ключ группировки бланка, по которому строки собраны вместе
    /// (`бланки`, `:42-54`).
    private var своёЗначение: String? {
        let имя = лаборатория.trimmingCharacters(in: .whitespaces)
        guard !имя.isEmpty else { return nil }
        return доступные.contains { $0.name == имя } ? nil : имя
    }

    var body: some View {
        TGSheet(title: .готовая(Fmt.notBlank(result.indicator) ?? String(localized: "Анализ")),
                subtitle: "строка бланка",
                closeTitle: "Закрыть") {
            TGCard(spacing: 0) {
                LabeledField(label: "Показатель") {
                    TextField("Т4 общий", text: $черновик.показатель)
                }
                TGDivider()
                Picker("Вид значения", selection: $черновик.вид) {
                    ForEach(ВидЗначения.allCases) { Text($0.подпись).tag($0) }
                }
                .pickerStyle(.segmented)

                if черновик.вид == .текстом {
                    TextField("результат словами", text: $черновик.текстом, axis: .vertical)
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)
                } else {
                    TGDivider()
                    LabeledField(label: "Число") {
                        TextField("с бланка", text: $черновик.число).keyboardType(.decimalPad)
                            .focused($фокус, equals: .число)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Единица") {
                        TextField("нг/дл", text: $черновик.единица)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    TGDivider()
                    LabeledField(label: "Норма от") {
                        TextField("с бланка", text: $черновик.нормаНиз).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаНиз)
                            .autocorrectionDisabled()
                    }
                    TGDivider()
                    LabeledField(label: "Норма до") {
                        TextField("с бланка", text: $черновик.нормаВерх).keyboardType(.decimalPad)
                            .focused($фокус, equals: .нормаВерх)
                            .autocorrectionDisabled()
                    }
                }
            }

            // MARK: Бланк — ПЯТЬ ПОЛЕЙ, которые нельзя было исправить
            //
            // **Замер 26.10.2026.** Создание (`сохранить` в
            // `LabResultEntryFlow`) писало `section`, `laboratory`,
            // `reportNumber`, `sampledOn`, `sampledAt`. Правка строки
            // переписывала только `indicator`, `unit`, значение
            // и норму — то есть опечатка в названии лаборатории,
            // в номере бланка и неверная дата забора были
            // **неисправимы навсегда**.
            //
            // Хуже всего номер: по нему идёт ГРУППИРОВКА бланков
            // (`бланки`, `:42-54`). Опечатка в номере рвала бланк
            // на две группы, человек это видел — и починить не мог
            // ничем, кроме удаления всех строк и повторного ввода
            // бланка с нуля.
            //
            // > **Поле, которое можно записать и нельзя переписать, —
            // > это не «почти правка». Это ловушка:** человек видит
            // > свою ошибку, видит форму правки и не находит в ней
            // > того, что ошиблось.
            TGCard(spacing: 0) {
                TGSectionHeader(title: "бланк",
                                subtitle: "общее для всех строк этого бланка")
                // Лаборатория — ИЗ СПРАВОЧНИКА, а не свободным текстом.
                // Здесь была ровно та беда, от которой справочник
                // и заведён: два экрана спрашивали одно и то же
                // по-разному — визит выбирал клинику пикером, анализ
                // набирал её руками, — и «Vet Riviera» с «вет ривьера»
                // становились разными организациями в одной карте.
                Picker("Лаборатория", selection: $лаборатория) {
                    Text("не указана").tag("")
                    if let своё = своёЗначение {
                        // Записанное до справочника. Подпись не врёт,
                        // что это выбор из списка.
                        Text(verbatim: своё).tag(своё)
                    }
                    ForEach(доступные) { Text(verbatim: $0.name).tag($0.name) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Token.Size.tapTarget)
                if доступные.isEmpty {
                    TGExplainer(text: "Справочник пуст. Клиники и лаборатории заводятся в «Здоровье» → «Клиники и лаборатории» — оттуда они и попадают в этот выбор.")
                }
                TGDivider()
                LabeledField(label: "Номер бланка") {
                    TextField("как на бланке", text: $номерБланка)
                }
                TGDivider()
                LabeledField(label: "Раздел") {
                    TextField("гормоны", text: $раздел)
                }
                TGDivider()
                DatePicker("Дата забора", selection: $датаЗабора, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGExplainer(text: "Номер связывает строки одного бланка между собой. Правка номера здесь переносит эту строку в другую группу — именно этим и чинят опечатку.")
            }

            TGCard {
                TGSectionHeader(title: "время забора")
                Toggle(isOn: $времяИзвестно) {
                    Text("Время забора известно").textStyle(AppFont.body)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if времяИзвестно {
                    DatePicker("Время забора", selection: $времяЗабора, displayedComponents: .hourAndMinute)
                        .frame(minHeight: Token.Size.tapTarget)
                }
                TGExplainer(text: времяИзвестно
                            ? "Часы от дозы приложение считает само — вводить их не нужно."
                            : "Без времени так и запишем — «время не указано». Это честнее, чем угадать: подставь мы «вероятно, утром», запись сказала бы врачу то, чего ты не вводил.")
            }

            // MARK: Отметка лаборатории
            //
            // **Долг закрыт 26.10.2026, и условие было ИСПОЛНЕНО,
            // а не отменено.** В голове `LabResultEntryFlow` (`:394`)
            // стояло: «Поле собирается за минуту, обязательство показа
            // — нет. Завести вместе с парным показом вердикта».
            // Красная линия проекта говорит то же: «поле
            // с обязательством показа вводить раньше показа нельзя».
            //
            // Замер 26.10.2026 — парный показ СУЩЕСТВУЕТ и достижим
            // человеком:
            //
            // ```
            // MedicalRecordCards.вердикт   «по нашей норме: …»
            //                              «лаборатория: …»
            //                              строками друг под другом,
            //                              каждая подписана
            // показ под `if let чтение`    labMark БЕЗ нашего вердикта
            //                              не рисуется по устройству
            // живой вход                   VetSummaryScreen:56,
            //                              а это «Здоровье» → «Сводка
            //                              врачу» — не галерея DEBUG
            // ```
            //
            // То есть инвариант «либо оба, либо ни одного» держит
            // не договорённость, а структура показа. Условие ввода
            // было «наличие парного показа», и оно выполнено, —
            // поэтому ввод заводится, а не откладывается.
            //
            // > **Запись о долге перестаёт называть долг в том же
            // > коммите, где долг закрыт.** Голова
            // > `LabResultEntryFlow` поправлена рядом.
            TGCard(spacing: 0) {
                LabeledField(label: "Отметка лаборатории") {
                    // Подсказка — слово-роль: конкретные «↓» или
                    // «норма» в примере читались бы как наш вердикт.
                    TextField("что отметила лаборатория", text: $черновик.отметка)
                }
                TGExplainer(text: "Это отметка самой лаборатории с бланка, а не вывод приложения. Расхождение с нашим счётом — находка, а не ошибка: референс у лабораторий разный.")
            }

            TGButton(title: "Удалить строку", variant: .destructive, size: .medium, systemImage: "trash") {
                удаляем = true
            }
        } footer: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Форма — по образцу запаса корма (`d569d01`):
            // строка над кнопкой, на ТОЙ ЖЕ величине, что ворота.
            VStack(spacing: Token.Space.s8) {
                if черновик.пустой {
                    Text("Назови показатель — так, как он написан в бланке")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: "Сохранить", isEnabled: !черновик.пустой) { сохранить() }
            }
        }
        .presentationDetents([.large])
        // Выход с цифровой клавиатуры.
        .готовоНадКлавиатурой { фокус = nil }
        .task { загрузить() }
        .confirmationDialog("Удалить строку?", isPresented: $удаляем, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                // Надгробие вместо `context.delete`: медкнижку читает
                // тот, кто сегодня везёт собаку к врачу, и строка,
                // удалённая у хозяйки, оставалась у него навсегда.
                let откат = ОбщееУдаление.удалить(result)
                guard context.persist(otherwise: откат) else {
                    Haptics.warning()
                    appState.showFailure("Не удалилось · нажми ещё раз")
                    return
                }
                Haptics.warning()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Строка уйдёт из списка и из отчёта врачу. Остальные строки этого бланка останутся.")
        }
    }

    private func загрузить() {
        guard !загружено else { return }
        черновик.показатель = result.indicator
        черновик.единица = result.unit
        черновик.нормаНиз = ЧислоСБланка.текст(result.referenceLow)
        черновик.нормаВерх = ЧислоСБланка.текст(result.referenceHigh)
        черновик.отметка = result.labMark
        // Поля бланка. Без этих шести строк форма открывалась с пустой
        // лабораторией и сегодняшней датой, и «Сохранить» затирало бы
        // верные значения — то есть правка одного показателя рвала бы
        // бланк сильнее, чем исходная опечатка.
        лаборатория = result.laboratory
        номерБланка = result.reportNumber
        раздел = result.section
        датаЗабора = result.sampledOn
        времяИзвестно = result.sampledAt != nil
        времяЗабора = result.sampledAt ?? result.sampledOn
        // Вид выводится из того, какое поле заполнено: две копии одного
        // решения разошлись бы молча.
        if let число = result.value {
            черновик.вид = .равно
            черновик.число = ЧислоСБланка.текст(число)
        } else if let ниже = result.belowLimit {
            черновик.вид = .ниже
            черновик.число = ЧислоСБланка.текст(ниже)
        } else if let выше = result.aboveLimit {
            черновик.вид = .выше
            черновик.число = ЧислоСБланка.текст(выше)
        } else if let текст = Fmt.notBlank(result.textValue ?? "") {
            черновик.вид = .текстом
            черновик.текстом = текст
        }
        загружено = true
    }

    private func сохранить() {
        let былПоказатель = result.indicator
        let былаЕдиница = result.unit
        let былоЗначение = result.value
        let былНиже = result.belowLimit
        let былВыше = result.aboveLimit
        let былТекст = result.textValue
        let былаНормаНиз = result.referenceLow
        let былаНормаВерх = result.referenceHigh
        let былаОтметка = result.labMark
        let былаЛаборатория = result.laboratory
        let былНомер = result.reportNumber
        let былРаздел = result.section
        let былаДата = result.sampledOn
        let былоВремя = result.sampledAt
        let былоИзменено = result.changedAt

        result.indicator = черновик.показатель.trimmingCharacters(in: .whitespaces)
        result.unit = черновик.единица.trimmingCharacters(in: .whitespaces)
        result.referenceLow = ЧислоСБланка.разобрать(черновик.нормаНиз)
        result.referenceHigh = ЧислоСБланка.разобрать(черновик.нормаВерх)
        result.labMark = черновик.отметка.trimmingCharacters(in: .whitespaces)
        // Пять полей бланка. До 26.10.2026 их тут не было, и опечатка
        // в них была неисправима навсегда.
        result.laboratory = лаборатория.trimmingCharacters(in: .whitespaces)
        result.reportNumber = номерБланка.trimmingCharacters(in: .whitespaces)
        result.section = раздел.trimmingCharacters(in: .whitespaces)
        result.sampledOn = датаЗабора
        result.sampledAt = времяИзвестно
            ? моментЗабора(день: датаЗабора, время: времяЗабора) : nil

        let число = ЧислоСБланка.разобрать(черновик.число)
        result.value = черновик.вид == .равно ? число : nil
        result.belowLimit = черновик.вид == .ниже ? число : nil
        result.aboveLimit = черновик.вид == .выше ? число : nil
        let текст = черновик.текстом.trimmingCharacters(in: .whitespaces)
        result.textValue = черновик.вид == .текстом && !текст.isEmpty ? текст : nil

        // Время правки на ЭТОМ телефоне — им решается спор двух телефонов
        // при обмене.
        result.changedAt = Date()

        guard context.persist(otherwise: {
            result.indicator = былПоказатель
            result.unit = былаЕдиница
            result.value = былоЗначение
            result.belowLimit = былНиже
            result.aboveLimit = былВыше
            result.textValue = былТекст
            result.referenceLow = былаНормаНиз
            result.referenceHigh = былаНормаВерх
            result.labMark = былаОтметка
            result.laboratory = былаЛаборатория
            result.reportNumber = былНомер
            result.section = былРаздел
            result.sampledOn = былаДата
            result.sampledAt = былоВремя
            result.changedAt = былоИзменено
        }) else {
            Haptics.warning()
            appState.showFailure("Не сохранилось · нажми «Сохранить» ещё раз")
            return
        }
        Haptics.success()
        dismiss()
    }
}
