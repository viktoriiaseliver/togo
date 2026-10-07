import SwiftUI
import SwiftData

/// Медкнижка внутри сводки для врача: анализы, визиты, диагнозы,
/// назначения.
///
/// # Зачем это здесь, а не отдельным экраном
///
/// **До 07.10.2026 у медкнижки не было ни одного экрана.** Обмен возил
/// её ко второму человеку, архив хранил сорок одно поле, круг
/// проверялся значениями — а посмотреть загруженную карту Стича было
/// негде. Виктория поставила сборку 273 и написала «часть функций
/// не работает»: отличить «сломано» от «нет поверхности» человек
/// не может по устройству.
///
/// > **Поверхность — часть функции, а не её оформление.** Пока её нет,
/// > каждая следующая сборка будет давать тот же отзыв, и правдой он
/// > будет каждый раз.
///
/// Хозяин — `VetSummaryScreen`, и это не экономия: сводка и есть тот
/// экран, который показывают врачу в кабинете. Фильтр периода на нём
/// уже стоит, и врачу он нужен ровно здесь — «анализы за этот месяц».
///
/// # Только чтение, и это названо заранее
///
/// Заведения записей руками нет. Данные приходят загрузкой архива,
/// и она работает. Формы ввода — отдельная работа: пятнадцать полей
/// у анализа, восемнадцать у рецепта, и каждое со своим правилом.
///
/// # Три правила показа, каждое оплачено
///
/// 1. **Значение рисуется тремя формами, а не одной.** `<0,1 нг/дл`
///    никогда не становится числом `0,1`; текстовый результат
///    бактериологии показывается текстом. Сведя их в одно, экран
///    отдал бы тихо неверное число вместо видимо неизвестного —
///    и сломал бы то, что обмен и архив везут правильно.
/// 2. **Отметка лаборатории показывается ТОЛЬКО вместе с нашим
///    вердиктом и подписанной, кто сказал.** Два «отклонения» рядом
///    без подписи — и человек прочтёт лабораторную галочку как наш
///    ответ. Нет вердикта — нет и отметки: одно без другого хуже,
///    чем ничего.
/// 3. **«Не записано, через сколько часов после дозы» — это ответ,**
///    а не пустота. `LabNorm.readingWord` различает четыре исхода,
///    и экран их не схлопывает.
///
/// # Чего этот файл не делает
///
/// Не считает ничего сам. Отклонение, коридор и время забора приходят
/// из `LabNorm` и `LabSampleTiming` — двух правил на одну мысль
/// не бывает, они расходятся на второй правке.
struct MedicalRecordCards: View {
    let dog: Dog?
    let from: Date
    let to: Date

    var body: some View {
        if dog?.labResults.isEmpty == false { labsCard }
        if dog?.vetVisits.isEmpty == false { visitsCard }
        if dog?.diagnoses.isEmpty == false { diagnosesCard }
        if dog?.prescriptions.isEmpty == false { prescriptionsCard }
    }

    // MARK: Анализы

    /// Анализы за период, сгруппированные по разделу бланка.
    ///
    /// **Группировка по разделу — требование модели, а не вкус:**
    /// гормоны, биохимия и бактериология несравнимы между собой,
    /// и общий список смешал бы их в одну колонку чисел.
    ///
    /// Раздел без имени собирает в себя всё, что его не заполнило, —
    /// поэтому пустой показывается своей строкой «без раздела»,
    /// а не сливается с первым попавшимся.
    private var labsCard: some View {
        TGCard {
            TGSectionHeader(title: "Анализы", subtitle: "за выбранный период")
            let разделы = сгруппированныеАнализы
            if разделы.isEmpty {
                Text("За этот период анализов нет")
                    .textStyle(AppFont.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(разделы, id: \.имя) { раздел in
                VStack(alignment: .leading, spacing: Token.Space.s8) {
                    Text(verbatim: раздел.имя)
                        .textStyle(AppFont.caps.color(Token.Ink.secondary))
                        .textCase(.uppercase)
                    ForEach(раздел.строки, id: \.persistentModelID) { анализ in
                        ЧастьАнализа(анализ: анализ, dog: dog)
                        if анализ.persistentModelID != раздел.строки.last?.persistentModelID {
                            TGDivider()
                        }
                    }
                }
            }
        }
    }

    /// **Шаги расписаны с явными типами, а не цепочкой.** SourceKit
    /// на первой редакции этого места ответил «the compiler is unable
    /// to type-check this expression in reasonable time»: `dog?.labResults
    /// ?? []` плюс два замыкания дают перебор, растущий степенью.
    ///
    /// Это тот же срыв типизатора, что держал CI красным шесть прогонов
    /// подряд, и он **единственный известный нам дефект, у которого
    /// присутствие в коде не означает присутствия в сборке**: локально
    /// собирается, на раннере нет. Поймано здесь до коммита —
    /// предупреждением редактора, а не чужой машиной.
    private var сгруппированныеАнализы: [(имя: String, строки: [LabResult])] {
        let все: [LabResult] = dog?.labResults ?? []
        let начало: Date = from
        let конец: Date = to
        var вПериоде: [LabResult] = все.filter { анализ in
            анализ.sampledOn >= начало && анализ.sampledOn <= конец
        }
        вПериоде.sort { $0.sampledOn > $1.sampledOn }
        var порядок: [String] = []
        var карта: [String: [LabResult]] = [:]
        for анализ in вПериоде {
            // Пустой раздел не сливается с чужим: ключ со значением
            // по умолчанию собрал бы в одну группу всё, что его
            // не заполнило.
            let имя = Fmt.notBlank(анализ.section) ?? String(localized: "без раздела")
            if карта[имя] == nil { порядок.append(имя) }
            карта[имя, default: []].append(анализ)
        }
        return порядок.map { (имя: $0, строки: карта[$0] ?? []) }
    }

    // MARK: Визиты

    private var visitsCard: some View {
        TGCard {
            TGSectionHeader(title: "Визиты")
            let визиты = (dog?.vetVisits ?? [])
                .filter { $0.date >= from && $0.date <= to }
                .sorted { $0.date > $1.date }
            if визиты.isEmpty {
                Text("За этот период визитов нет")
                    .textStyle(AppFont.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(визиты, id: \.persistentModelID) { визит in
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(verbatim: Fmt.shortDay(визит.date))
                            .textStyle(AppFont.body)
                        // Повод — через `title` перечисления, то есть
                        // через каталог: «онлайн» это наше слово,
                        // а не данные с бланка. Показать его сырым
                        // значило бы написать французу `online`.
                        Text(визит.reason.title)
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                        Spacer(minLength: Token.Space.s8)
                        если(визит.clinic?.name) { имя in
                            Text(verbatim: имя)
                                .textStyle(AppFont.caption.color(Token.Ink.secondary))
                        }
                    }
                    если(Fmt.notBlank(визит.doctor)) { врач in
                        Text(verbatim: врач).textStyle(AppFont.caption)
                    }
                    если(Fmt.notBlank(визит.conclusion)) { заключение in
                        Text(verbatim: заключение).textStyle(AppFont.body).wraps()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if визит.persistentModelID != визиты.last?.persistentModelID { TGDivider() }
            }
        }
    }

    // MARK: Диагнозы

    /// Диагнозы — **без фильтра периода, и это решение.**
    ///
    /// Диагноз не событие месяца: подтверждённый гипотиреоз, поставленный
    /// в августе, нужен врачу в октябре ровно так же. Отфильтровав его
    /// периодом, экран скрыл бы главное про собаку в тот момент, когда
    /// про это и спрашивают.
    ///
    /// Снятые показываются тоже — и помечены: «снят» это часть истории,
    /// а не её отсутствие. Спрятав их, мы заставили бы врача заново
    /// проверять то, что уже проверяли.
    private var diagnosesCard: some View {
        TGCard {
            TGSectionHeader(title: "Диагнозы", subtitle: "за всё время, не только за период")
            let диагнозы = (dog?.diagnoses ?? []).sorted { $0.madeOn > $1.madeOn }
            ForEach(диагнозы, id: \.persistentModelID) { диагноз in
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(verbatim: Fmt.notBlank(диагноз.wording)
                             ?? String(localized: "без формулировки"))
                            .textStyle(AppFont.body)
                            .wraps()
                        Spacer(minLength: Token.Space.s8)
                        // Статус — наше слово и наш вывод, поэтому через
                        // каталог. По подтверждённому лечат, по гипотезе
                        // ищут, снятый не лечат вовсе: три разные новости,
                        // и одной подписью их покрывать нельзя.
                        Text(диагноз.status.title)
                            .textStyle(AppFont.caption.color(цвет(диагноз.status)))
                    }
                    Text(verbatim: Fmt.shortDay(диагноз.madeOn))
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    если(Fmt.notBlank(диагноз.madeBy)) { кем in
                        Text(verbatim: кем).textStyle(AppFont.caption)
                    }
                    если(Fmt.notBlank(диагноз.evidence)) { чем in
                        Text(verbatim: чем)
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if диагноз.persistentModelID != диагнозы.last?.persistentModelID { TGDivider() }
            }
        }
    }

    /// Цвет статуса — **подпорка к слову, а не замена ему.**
    ///
    /// Слово стоит рядом всегда: срочность и состояние никогда
    /// не передаются одним цветом. Здесь цвет лишь помогает найти
    /// строку глазами.
    private func цвет(_ статус: DiagnosisStatus) -> Color {
        switch статус {
        case .confirmed: Token.Ink.primary
        case .hypothesis: Token.Ink.secondary
        case .withdrawn: Token.Ink.secondary
        }
    }

    // MARK: Назначения

    private var prescriptionsCard: some View {
        TGCard {
            TGSectionHeader(title: "Назначения")
            let рецепты = (dog?.prescriptions ?? [])
                .filter { $0.date >= from && $0.date <= to }
                .sorted { $0.date > $1.date }
            if рецепты.isEmpty {
                Text("За этот период назначений нет")
                    .textStyle(AppFont.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(рецепты, id: \.persistentModelID) { рецепт in
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(verbatim: Fmt.notBlank(рецепт.medicationName)
                             ?? String(localized: "без названия"))
                            .textStyle(AppFont.body)
                        Spacer(minLength: Token.Space.s8)
                        Text(verbatim: Fmt.shortDay(рецепт.date))
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                    если(Fmt.notBlank(рецепт.dosage)) { доза in
                        Text(verbatim: [доза, Fmt.notBlank(рецепт.schedule)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .textStyle(AppFont.body)
                    }
                    // Вес на дату назначения — ЧАСТЬ назначения, а не
                    // справка: доза считается от него, и проверить её
                    // задним числом больше неоткуда.
                    если(рецепт.dogWeightKg) { вес in
                        Text("вес на дату: \(Fmt.weight(вес))")
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                    если(рецепт.pharmacyForm.flatMap(Fmt.notBlank)) { форма in
                        Text(verbatim: форма)
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                    окноКонтроля(рецепт)
                    если(Fmt.notBlank(рецепт.instruction)) { как in
                        Text(verbatim: как).textStyle(AppFont.caption).wraps()
                    }
                    если(Fmt.notBlank(рецепт.source)) { откуда in
                        Text(verbatim: откуда)
                            .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if рецепт.persistentModelID != рецепты.last?.persistentModelID { TGDivider() }
            }
        }
    }

    /// Срок контроля — **окном, а не датой.**
    ///
    /// Три врача назвали три интервала: «4–6 недель», «3 недели»,
    /// «4–8 недель». Свести к одной дате значило бы придумать число
    /// за врача, и экран этого не делает — он показывает то, что
    /// написано в бланке.
    @ViewBuilder
    private func окноКонтроля(_ рецепт: Prescription) -> some View {
        if рецепт.controlFromWeeks > 0 || рецепт.controlToWeeks > 0 {
            if рецепт.controlFromWeeks == рецепт.controlToWeeks {
                Text("контроль через \(рецепт.controlFromWeeks) нед.")
                    .textStyle(AppFont.caption.color(Token.Ink.secondary))
            } else {
                Text("контроль через \(рецепт.controlFromWeeks)–\(рецепт.controlToWeeks) нед.")
                    .textStyle(AppFont.caption.color(Token.Ink.secondary))
            }
        }
    }

    /// Показать содержимое, только если значение есть.
    ///
    /// Своё, а не `if let` в теле: у `ViewBuilder` разветвление на каждое
    /// необязательное поле раздувает тип выражения, а срыв типизатора
    /// у нас уже стоил шести прогонов CI подряд.
    @ViewBuilder
    private func если<T, V: View>(_ значение: T?,
                                  @ViewBuilder content: (T) -> V) -> some View {
        if let значение { content(значение) }
    }
}

// MARK: - Строка анализа

/// Одна строка анализа: показатель, значение, чем прочитано.
///
/// Вынесена отдельной структурой нарочно — не ради красоты, а чтобы
/// `labsCard` не стал одним выражением на сорок ветвей: срыв типизатора
/// держал CI красным шесть прогонов подряд, и присутствие такого
/// выражения в коде не означает присутствия в сборке.
private struct ЧастьАнализа: View {
    let анализ: LabResult
    let dog: Dog?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(verbatim: Fmt.notBlank(анализ.indicator)
                     ?? String(localized: "без названия"))
                    .textStyle(AppFont.body)
                Spacer(minLength: Token.Space.s8)
                Text(verbatim: значение)
                    .textStyle(AppFont.body)
            }
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(verbatim: Fmt.shortDay(анализ.sampledOn))
                    .textStyle(AppFont.caption.color(Token.Ink.secondary))
                if let лаборатория = Fmt.notBlank(анализ.laboratory) {
                    Text(verbatim: лаборатория)
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                }
            }
            вердикт
            если(Fmt.notBlank(анализ.note)) { заметка in
                Text(verbatim: заметка)
                    .textStyle(AppFont.caption.color(Token.Ink.secondary))
                    .wraps()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Значение тремя формами.
    ///
    /// **Предел обнаружения не становится числом.** `<0,1` — это
    /// не `0,1`: записав пределом, экран показал бы тихо неверное
    /// значение вместо видимо неизвестного, а от этого числа считают
    /// дозу.
    ///
    /// Текстовый результат — четвёртая форма: бактериология числа
    /// не даёт вовсе, и девять строк карты Стича без неё не влезают.
    private var значение: String {
        let единица = Fmt.notBlank(анализ.unit).map { " \($0)" } ?? ""
        if let число = анализ.value { return Fmt.decimal(число) + единица }
        if let ниже = анализ.belowLimit { return "<\(Fmt.decimal(ниже))" + единица }
        if let выше = анализ.aboveLimit { return ">\(Fmt.decimal(выше))" + единица }
        if let текст = Fmt.notBlank(анализ.textValue ?? "") { return текст }
        return String(localized: "нет значения")
    }

    /// Чем прочитан результат — и чья это отметка.
    ///
    /// **Отметка лаборатории показывается только ВМЕСТЕ с нашим
    /// вердиктом и подписанной.** Два «отклонения» рядом без подписи
    /// однажды сравняются, и человек прочтёт лабораторную галочку
    /// как наш ответ. Нет вердикта — нет и отметки: одно без другого
    /// хуже, чем ничего, потому что расхождение станет невидимым,
    /// а источник неизвестным.
    ///
    /// Расхождение между ними — **находка, а не ошибка**: референс Т4
    /// в карте менялся трижды, и лаборатория считала по своему.
    /// **Строками друг под другом, а не в ряд — и это поймал КАДР,
    /// а не прогон.**
    ///
    /// Первая редакция ставила обе подписи в `HStack`. Тест был
    /// зелёным: отметок лаборатории не больше, чем наших вердиктов,
    /// инвариант цел. На кадре вышло вот что:
    ///
    /// ```
    /// по нашей норме:   лаборатория: норма
    /// ниже нормы
    /// ```
    ///
    /// Длинный вердикт переносится, короткая отметка стоит рядом —
    /// и **слова перемешиваются**: «норма» читается как конец нашей
    /// фразы, «ниже нормы» повисает ничьим. Второй случай был хуже:
    /// «по нашей норме: не ⟨отметка⟩ записано, через сколько часов».
    ///
    /// То есть правило «показывать только вместе и подписанными»
    /// соблюдено в коде и **нарушено на экране**: подписи есть,
    /// а кому что принадлежит — не видно.
    ///
    /// > **Тест проверил, что подписи СТОЯТ. Что они читаются,
    /// > проверить может только кадр.**
    ///
    /// Это тот же зазор, что между «верно ли посчитано» и «верно ли
    /// сказано», и он тут стоил бы ровно того, ради чего правило
    /// заводилось: человек прочёл бы лабораторную отметку как наш
    /// ответ.
    @ViewBuilder
    private var вердикт: some View {
        if let чтение {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("по нашей норме: \(LabNorm.readingWord(чтение))")
                    .textStyle(AppFont.caption)
                    .wraps()
                если(Fmt.notBlank(анализ.labMark)) { отметка in
                    Text("лаборатория: \(отметка)")
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                        .wraps()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Чтение приходит из `LabNorm` целиком. Экран ничего не считает
    /// сам: два правила на одну мысль расходятся на второй правке.
    private var чтение: LabNorm.Reading? {
        guard let величина = анализ.measuredValue else { return nil }
        return LabNorm.reading(value: величина,
                               reference: анализ.reference,
                               band: коридор,
                               hoursAfterDose: часыПослеДозы)
    }

    /// Коридор — только у того показателя, для которого он назван,
    /// и только при активном лечении. Приложить его к чужому анализу
    /// значило бы выдать одну мерку за другую.
    private var коридор: LabNorm.TherapeuticBand? {
        guard dog?.isOnTreatment == true else { return nil }
        guard анализ.indicator.localizedCaseInsensitiveContains("т4")
                || анализ.indicator.localizedCaseInsensitiveContains("t4") else { return nil }
        return .totalT4
    }

    /// Часы после дозы — из отметок приёма, а не из догадки.
    /// Нет отметки — `nil`, и `LabNorm` скажет об этом словом,
    /// а не промолчит.
    private var часыПослеДозы: Double? {
        guard let взят = анализ.sampledAt else { return nil }
        let приёмы = (dog?.medications ?? [])
            .flatMap(\.doses)
            .compactMap(\.givenAt)
            .filter { $0 <= взят }
        guard let последняя = приёмы.max() else { return nil }
        let часы = взят.timeIntervalSince(последняя) / 3600
        return часы >= 0 ? часы : nil
    }

    @ViewBuilder
    private func если<T, V: View>(_ значение: T?,
                                  @ViewBuilder content: (T) -> V) -> some View {
        if let значение { content(значение) }
    }
}
