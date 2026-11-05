import SwiftUI
import SwiftData

/// История · фильтры-чипы, полоса выходов, ритм, календарь, эпизоды.
///
/// **Переписано под дизайн iOS 28, тема «Кино»** — решение Виктории
/// 22.10.2026. Эталон — `Дизайн/эталонные-кадры/ios28-кино-22.10/10.png`,
/// и ниже исполнен **кадр**, а не проза README: где они расходятся,
/// расхождение названо в отчёте.
///
/// Что поменялось в показе и почему:
///
/// ```
/// было                        стало (кадр 10)
/// шапка-плакат, синяя полоса  фото под шапкой, кикер «ВСЁ · 30 ДНЕЙ»,
///                             заголовок 36 и одна кнопка «…»
/// шестерёнка в баре           её нет: «Настройки» — пункт меню «…»
/// сегментированный выбор      чипы-пилюли с прокруткой вбок
/// график Swift Charts с осями полоса столбиков без осей
/// ```
///
/// **Сегментированный выбор убран не по вкусу.** У него измеренный
/// дефект: он делит ширину поровну и **обрезает**, а не переносит —
/// кадр 28.09 показал «Симпто…». Прежняя починка разводила два органа
/// управления по размеру текста (`.menu` на доступных кеглях). Чипы
/// закрывают тот же дефект одним органом: они не делят ширину,
/// подпись переносится целиком, а лишние уезжают за край прокруткой.
///
/// Точка на дне календаря: сине-зелёная — обычный день, терракот —
/// инцидент или кровь, серо-коричневая — медицинское событие; форма
/// значка разная, потому что цветом одним день не различить.
struct HistoryScreen: View {
    @Query private var dogs: [Dog]
    /// Все эпизоды хранилища. Экран показывает только касающиеся
    /// открытой собаки — `эпизоды` ниже (V10, `Episode.dogID`).
    @Query(sort: \Episode.startedAt) private var всеЭпизоды: [Episode]
    @Query private var members: [FamilyMember]
    @Query private var daysOut: [DayOut]

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var closing: Episode?
    /// Эпизод, который человек собрался удалить.
    @State private var удаляемый: Episode?
    /// Человек собрался убрать все закончившиеся разом.
    @State private var убратьЗакончившиеся = false
    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var filter: HistoryFilter = .all
    @State private var selectedDay: Date?
    /// Настройки открываются из меню «…» — шестерёнки в шапке больше нет.
    /// Переход делает хозяин экрана: `NavigationLink` внутри `Menu`
    /// срабатывает непредсказуемо (разбор у `HeaderMenu`).
    @State private var показатьНастройки = false
    /// Прошедший день с собакой, открытый на правку.
    @State private var правимыйДень: DayOut?

    private var dog: Dog? { appState.activeDog(from: dogs) }
    private var events: [LogEvent] { Diary.active(dog?.events ?? []) }

    var body: some View {
        NavigationStack {
            КиноЭкран(экран: .history,
                      кикер: .готовая(кикер),
                      заголовок: "История",
                      настройки: { показатьНастройки = true }) {
                // # Дневник читается ОДИН раз на перерисовку
                //
                // `events` — вычисляемое: `Diary.active` над всеми записями
                // собаки. До 29.10.2026 его звали шесть мест одного `body`
                // (пустота, отбор, ритм, долгие дни, индекс календаря,
                // индекс полосы), и индекс по дням строился дважды —
                // полосой и календарём. Каждое касание чипа платило
                // за шесть проходов по дневнику вместо одного.
                let события = events
                if события.isEmpty {
                    EmptyStateCard(
                        subject: .history,
                        title: "История начнётся с первой записи",
                        // «Графики по стулу и весу» сняты 29.10.2026:
                        // у веса графика нет нарочно (`полосаВеса`),
                        // и обещание читалось как пропавшая функция.
                        message: "Здесь появятся календарь с отметкой на каждый день, полоса за 30 дней и эпизоды. Заполнять заранее ничего не надо.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    let индекс = Diary.поДням(события.filter(filter.matches))
                    чипыФильтра
                    if filter == .weight { полосаВеса } else { полосаВыходов(индекс) }
                    ритмВыходов(события)
                    показатьВрачу
                    dayOutCard(события)
                    прошедшиеДни
                    месяцШапкой
                    MonthCalendar(month: $month, поДням: индекс,
                                  дниВзвешиваний: filter == .weight ? дниВзвешиваний : [],
                                  onSelect: { selectedDay = $0 })
                    episodesCard
                }
            }
            .usageScreen(.history)
            .navigationDestination(isPresented: $показатьНастройки) {
                SettingsScreen()
            }
            .sheet(item: $правимыйДень) { day in DayOutEditSheet(day: day) }
            .sheet(item: Binding(get: { selectedDay.map(DayRef.init) },
                                 set: { selectedDay = $0?.date })) { ref in
                DayReadingScreen(day: ref.date, events: events,
                                 showsAuthor: members.count > 1,
                                 взвешивания: (dog?.weights ?? [])
                                    .filter { Calendar.current.isDate($0.date, inSameDayAs: ref.date) }
                                    .sorted { $0.date < $1.date })
            }
            .confirmationDialog("Закрыть эпизод?",
                                isPresented: Binding(get: { closing != nil },
                                                     set: { if !$0 { closing = nil } }),
                                titleVisibility: .visible,
                                presenting: closing) { episode in
                Button("Закрыть") { close(episode) }
                Button("Ещё рано", role: .cancel) { closing = nil }
            } message: { _ in
                Text("Записи останутся в истории. Вердикт «просится» снова начнёт считаться по обычным промежуткам — во время эпизода он не считается совсем.")
            }
            .confirmationDialog("Удалить эпизод?",
                                isPresented: Binding(get: { удаляемый != nil },
                                                     set: { if !$0 { удаляемый = nil } }),
                                titleVisibility: .visible,
                                presenting: удаляемый) { episode in
                Button("Удалить", role: .destructive) { удалить(episode) }
                Button("Оставить", role: .cancel) { удаляемый = nil }
            } message: { _ in
                // Говорим ровно то, что случится, и ровно то, что НЕ
                // случится. Человек боится потерять записи — а теряется
                // только объединение их в эпизод.
                Text("Сами записи — инциденты, стул, дозы — останутся: удаляется только объединение их в эпизод. Если инциденты повторятся, приложение поднимет эпизод заново.")
            }
            .confirmationDialog("Убрать закончившиеся эпизоды?",
                                isPresented: $убратьЗакончившиеся,
                                titleVisibility: .visible) {
                Button("Убрать \(закончившиеся.count)", role: .destructive) {
                    убратьВсеЗакончившиеся()
                }
                Button("Оставить", role: .cancel) { убратьЗакончившиеся = false }
            } message: {
                // Идущий эпизод не трогаем и говорим об этом: он гасит
                // вердикт «просится», и человек, убравший его случайно,
                // не поймёт, почему подсказки вдруг вернулись.
                Text("Уберутся только те, что уже закончились. Идущий останется — его закрывают кнопкой «Собаке лучше — закрыть». Записи останутся все: удаляется только объединение их в эпизод.")
            }
        }
    }

    /// Кикер шапки: что выбрано и за какой срок. На кадре 10 — «ВСЁ · 30 ДНЕЙ».
    ///
    /// Собирается точкой-разделителем, а не грамматикой: склейки фраз
    /// хендофф переносить запрещает, а « · » между двумя готовыми
    /// строками переводить нечем и не нужно.
    private var кикер: String {
        [filter.title, String(localized: "30 дней")].joined(separator: " · ")
    }

    /// Чипы-пилюли с прокруткой вбок. Выбранный — белый с тёмной
    /// подписью, как главная кнопка темы «Кино».
    private var чипыФильтра: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Token.Space.s8) {
                ForEach(HistoryFilter.allCases, id: \.self) { вид in
                    КиноЧип(подпись: .готовая(вид.title),
                            выбран: вид == filter) {
                        filter = вид
                    }
                }
            }
            .padding(.vertical, Token.Space.s2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Фильтр")
    }

    // MARK: Полоса за тридцать дней

    /// Кадр 10: заголовок слева, срок справа, столбики без осей,
    /// пояснение под ними.
    ///
    /// **Осей нет нарочно.** У столбика без подписи единственный смысл —
    /// «выше или ниже соседнего», и ось месяца этого не добавляла:
    /// на тридцати днях подписи всё равно рисовались через одну.
    /// Что именно на полосе — говорит строка под ней, а не ось.
    private func полосаВыходов(_ индекс: [Date: [LogEvent]]) -> some View {
        // Точки считаются ОДИН раз на всю карточку. Прежде тут стояли
        // `chartPoints` и `тревожныеДни` рядом — два обращения, и каждое
        // строило весь тридцатидневный набор заново.
        let столбики = точки(индекс)
        return TGCard {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(.готовая(filter.chartName)).textStyle(AppFont.cardTitle).wraps()
                Spacer(minLength: Token.Space.s8)
                Text("30 дней").textStyle(AppFont.caption).wraps()
            }
            КиноСтолбики(значения: столбики.map(\.value),
                         тревожные: тревожные(столбики))
            Text(filter.chartExplainer).textStyle(AppFont.caption).wraps()
            TGDivider()
            Text("Приложение не ставит диагнозов. Оно умеет показать этот график врачу — вместе с датами еды и препаратов за те же дни.")
                .textStyle(AppFont.caption)
                .wraps()
        }
    }

    // MARK: Вес

    /// # Фильтр «Вес» не рисовал НИЧЕГО — и не мог
    ///
    /// Замер 29.10.2026. Фильтр спрашивал `LogEvent.kind == .weight`,
    /// а взвешивания живут не в ленте, а отдельной моделью
    /// `WeightEntry` (`Dog.weights`): их пишет `WeightScreen.save()`,
    /// и `LogEvent` с видом `.weight` не заводит в `Togo/` никто.
    /// Сверху `HistoryFilter.value` для `.weight` возвращал `0`
    /// литералом. Итог — тридцать пустых столбиков, пустой календарь
    /// и пояснение про «зелёную полосу коридора», которой нет.
    ///
    /// > **Фильтр смотрел туда, где предмета не бывает.** Три слоя
    /// > (отбор, значение, пояснение) были согласны друг с другом
    /// > и все трое молчали.
    ///
    /// Столбиков у веса нет нарочно: у полосы потолок — максимум,
    /// и 4,1 против 4,3 кг вышли бы одинаковой высоты. Вес читают
    /// числом, поэтому здесь — последний замер крупно и список
    /// взвешиваний за тот же срок, что у соседних фильтров.
    private var взвешиванияЗаМесяц: [WeightEntry] {
        let calendar = Calendar.current
        let начало = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) ?? .now
        return (dog?.weights ?? [])
            .filter { $0.date >= начало }
            .sorted { $0.date > $1.date }
    }

    /// Дни, в которые взвешивали, — для точки в календаре.
    ///
    /// Без служебного: прогрев схемы (`CloudKitSchemaWarmup`) пишет
    /// взвешивание датой 2001 года, и ленте его не показывает
    /// `Diary.служебная`, а сюда оно до 29.10.2026 доезжало.
    /// Порог тот же, не копия: `SharedDiaryOutgoing.раньшеПриложения`.
    private var дниВзвешиваний: Set<Date> {
        let calendar = Calendar.current
        return Set((dog?.weights ?? [])
            .filter { $0.date >= SharedDiaryOutgoing.раньшеПриложения }
            .map { calendar.startOfDay(for: $0.date) })
    }

    private var полосаВеса: some View {
        let замеры = взвешиванияЗаМесяц
        return TGCard {
            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                Text(.готовая(filter.chartName)).textStyle(AppFont.cardTitle).wraps()
                Spacer(minLength: Token.Space.s8)
                Text("30 дней").textStyle(AppFont.caption).wraps()
            }
            if let последний = замеры.first {
                // Последний замер — крупно и со своей датой, а в списке
                // под ним его больше нет. До 29.10.2026 он стоял дважды:
                // числом и первой строкой списка с тем же числом.
                Text(Fmt.weight(последний.kg)).textStyle(AppFont.display)
                Text(Fmt.shortDay(последний.date)).textStyle(AppFont.caption)
                ForEach(замеры.dropFirst().prefix(10)) { замер in
                    HStack {
                        Text(Fmt.shortDay(замер.date)).textStyle(AppFont.caption)
                        Spacer()
                        Text(Fmt.weight(замер.kg)).textStyle(AppFont.numeric(Token.FontSize.meta))
                    }
                }
            } else if appState.can(.seeMedical) {
                TGExplainer(text: "За эти 30 дней взвешиваний нет. Записать вес — «Здоровье» → «Вес».")
            } else {
                // Без `.seeMedical` вкладки «Здоровье» нет вовсе
                // (`RootView`), и дорога в неё вела бы в пустоту.
                TGExplainer(text: "За эти 30 дней взвешиваний нет.")
            }
            if let low = dog?.targetWeightLow, let high = dog?.targetWeightHigh {
                // «от врача», а не «поставил врач»: пол врача
                // приложению неизвестен.
                Text("цель \(Fmt.weight(low)) — \(Fmt.weight(high)) · от врача").textStyle(AppFont.caption)
            }
            if !замеры.isEmpty {
                Text(filter.chartExplainer).textStyle(AppFont.caption).wraps()
            }
        }
    }

    private func тревожные(_ точки: [HistoryPoint]) -> Set<Int> {
        Set(точки.enumerated().compactMap { $1.isAlarm ? $0 : nil })
    }

    /// Отобранные записи, разложенные по дням.
    ///
    /// **Одно вычисление на весь экран, и это не украшение.** Прежде
    /// `chartPoints` звал `Diary.onDay(filtered, день)` в цикле по
    /// тридцати дням, а `filtered` — вычисляемое свойство: оно
    /// пересчитывалось все тридцать раз, и каждый раз фильтровало весь
    /// дневник. Календарь делал то же сорок два раза. Разбор —
    /// `Diary.поДням`.
    ///
    /// С 29.10.2026 индекс строится в `body` один раз и раздаётся
    /// полосе и календарю аргументом: вычисляемым свойством он
    /// строился бы каждым читателем заново.
    /// Тридцать точек из готового индекса: день достаётся за O(1),
    /// отсутствие ключа значит «записей не было» — так условились
    /// в `Diary.поДням`.
    private func точки(_ индекс: [Date: [LogEvent]]) -> [HistoryPoint] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) ?? .now
        return (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayEvents = индекс[calendar.startOfDay(for: day)] ?? []
            return HistoryPoint(day: day, value: значение(dayEvents),
                                isAlarm: dayEvents.contains(where: \.raisesAlarm))
        }
    }

    /// Высота столбика за день.
    ///
    /// # «Выходы» считают ВЫХОДЫ, а не отметки — с 29.10.2026
    ///
    /// Прежде полоса брала `events.filter { $0.kind == .outing }.count`,
    /// то есть СОБЫТИЯ: прогулка с тремя отметками «пописал» давала
    /// здесь 3, а «Сегодня» за тот же день — 1 (`TimelineBuilder
    /// .outingsCount` считает блоки). Расхождение было названо
    /// в `OutingsCountTests.границы` и ждало решения; решение одно —
    /// у «сколько раз выходили» не может быть двух ответов
    /// на двух вкладках.
    ///
    /// Считается здесь, а не в `HistoryFilter.value`: перечисление
    /// `nonisolated`, а `TimelineBuilder` живёт на главном акторе
    /// приложения. Индекс дня уже отобран через `Diary.active`,
    /// поэтому `blocks` зовётся на готовом дне, без второго прохода
    /// по дневнику.
    private func значение(_ dayEvents: [LogEvent]) -> Double {
        switch filter {
        case .all: Double(TimelineBuilder.blocks(dayEvents).filter(\.isOuting).count)
        default: filter.value(for: dayEvents)
        }
    }

    // MARK: Ритм

    /// «Как часто гуляете» блоком Metric — кадр 10: крупное число,
    /// единица рядом, зеркало под ним.
    ///
    /// **`WalkRhythmCard` СНЕСЕНА 23.10.2026, и это закрыто, а не
    /// отложено.** Прежняя редакция этой строки говорила «здесь больше
    /// не зовётся… решение не моё»: тогда это было верно — файл был
    /// чужой. Замер 23.10 показал, что без места вызова осталась
    /// не одна ветка, а **весь тип**: `compact` держался на `NeedsSheet`
    /// и уехал в `4e6e399`, полная ветка — здесь, в `3e8eed6`.
    /// Ноль вызовов при живом контроле (`КиноМетрика(` — 2,
    /// `HeaderMenu(` — 3).
    ///
    /// > Что при этом потеряно, названо там, где лежит предмет, а не
    /// > здесь: `usualTimes` и `longestIndoors` в `WalkRhythm.swift`
    /// > остались без показывающего читателя. Этот блок показывает
    /// > только `outingsPerDay` — так решено кадром 10, и пересматривать
    /// > это уборкой нельзя.
    @ViewBuilder
    private func ритмВыходов(_ события: [LogEvent]) -> some View {
        let ритм = WalkRhythmAnalyzer.rhythm(events: события)
        if ритм.isReliable {
            КиноМетрика(
                шапка: "как часто гуляете",
                число: Fmt.decimal(ритм.outingsPerDay),
                единица: .готовая([String(localized: "выходов в день"),
                                   String(localized: "2 недели")].joined(separator: " · ")),
                пояснение: "Это не норма, а зеркало: сравнивать стоит не с чужой собакой, а с собой месяц назад."
            )
        } else {
            TGCard {
                TGSectionHeader(title: "как часто гуляете")
                TGExplainer(text: "Нужно хотя бы \(Fmt.days(WalkRhythm.minimumDays)) с записями — пока их \(ритм.days). Просто продолжай отмечать выходы.")
            }
        }
    }

    /// Что бывает после долгих дней с собакой.
    ///
    /// Причинность приложение не утверждает: оно показывает совпадение
    /// и оставляет вывод человеку. Этого хватает, чтобы прийти к врачу
    /// не с «ей плохо», а с «после долгих дней у неё вот что».
    @ViewBuilder
    private func dayOutCard(_ события: [LogEvent]) -> some View {
        let mine = daysOut.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
        let trace = DayOutAnalyzer.trace(daysOut: mine, events: события,
                                         norm: dog?.dailyGrams ?? 0)
        if !trace.findings(пол: dog?.sex).isEmpty {
            // # Род собаки — у `РодСобаки`, а не вписан (29.10.2026)
            //
            // Здесь стояло «где она была с тобой» и «она иногда вялая»
            // при любом поле, а `часов` — числом без склонения. Подпись
            // собрана из двух готовых строк: «по 3 дням» и «6 часов»
            // склоняет каталог, фразу вокруг — род.
            //
            // «Приложение не ставит диагнозов» снято из пояснения:
            // та же фраза стоит под полосой выше, на одном экране —
            // дважды.
            let дням = String(localized: "\(trace.longDays) дням")
            let часов = String(localized: "\(Int(DayOut.longDayHours)) часов")
            TGCard {
                Text("После долгих дней дома").textStyle(AppFont.cardTitle).wraps()
                Text(.готовая(РодСобаки.форма(
                    dog,
                    он: String(localized: "по \(дням), когда он был с тобой дольше \(часов)"),
                    она: String(localized: "по \(дням), когда она была с тобой дольше \(часов)"),
                    нейтрально: { String(localized: "по \(дням), когда собака была с тобой дольше \(часов)") }
                )))
                .textStyle(AppFont.caption)
                .wraps()
                ForEach(trace.findings(пол: dog?.sex), id: \.self) { line in
                    Text(verbatim: "• " + line).textStyle(AppFont.caption).wraps()
                }
                TGDivider()
                TGExplainer(text: .готовая(РодСобаки.форма(
                    dog,
                    он: String(localized: "Это совпадение, а не причина. Но показать эту строку врачу полезнее, чем сказать «он иногда вялый»."),
                    она: String(localized: "Это совпадение, а не причина. Но показать эту строку врачу полезнее, чем сказать «она иногда вялая»."),
                    нейтрально: { String(localized: "Это совпадение, а не причина. Но показать эту строку врачу полезнее, чем сказать «собака иногда вялая».") }
                )))
            }
        }
    }

    /// Прошедшие дни с собакой — с дорогой к правке.
    ///
    /// **До 29.10.2026 прошедшего дня не было видно нигде**, кроме
    /// как числом в «После долгих дней»: итог показывался один раз,
    /// при «Закончить», и после него день нельзя было ни найти,
    /// ни поправить, ни убрать. Десять последних — потому что правят
    /// недавнее: забыли закончить вчера, а не в прошлом году.
    @ViewBuilder
    private var прошедшиеДни: some View {
        let мои = daysOut
            .filter { $0.dog?.persistentModelID == dog?.persistentModelID && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(10)
        // Правка и удаление прошедшего дня — за `.editRecords`, как
        // у записей ленты. До 29.10.2026 лист правки открывал любой,
        // в том числе наблюдатель, и «Удалить этот день» у него
        // срабатывало. Без права строки остаются — день виден, —
        // но без стрелки: обещать дверь, которой нет, нельзя.
        let можноПравить = appState.can(.editRecords)
        if !мои.isEmpty {
            TGCard {
                TGSectionHeader(title: "дни с собакой")
                ForEach(Array(мои)) { day in
                    if можноПравить {
                        Button { правимыйДень = day } label: {
                            строкаДня(day, соСтрелкой: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        строкаДня(day, соСтрелкой: false)
                    }
                }
            }
        }
    }

    private func строкаДня(_ day: DayOut, соСтрелкой: Bool) -> some View {
        HStack {
            Text(Fmt.shortDay(day.startedAt)).textStyle(AppFont.body)
            Spacer()
            Text(Fmt.gap(day.duration())).textStyle(AppFont.numeric(Token.FontSize.meta))
            if соСтрелкой {
                Image(systemName: "chevron.right")
                    .font(.system(size: Token.Size.iconSm))
                    .foregroundStyle(Token.Ink.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
        .contentShape(Rectangle())
    }

    // MARK: Календарь

    /// Месяц прописными над карточкой — кадр 10 («ОКТЯБРЬ 2026 Г»).
    /// Стрелки остались: без них из октября не выйти, а листание месяца
    /// это единственный способ дойти до прошлого года.
    private var месяцШапкой: some View {
        HStack(spacing: Token.Space.s8) {
            Text(verbatim: month.formatted(.dateTime.month(.wide).year()))
                .textStyle(AppFont.caps)
                .textCase(.uppercase)
                .wraps()
            Spacer(minLength: Token.Space.s8)
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Предыдущий месяц")
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Следующий месяц")
            .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Token.Ink.secondary)
    }

    private func shiftMonth(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeInOut(duration: Token.Duration.quick)) { month = next }
    }

    // MARK: Эпизоды

    /// # Порядок считается ОДИН раз, и разделитель смотрит на него же
    ///
    /// До 29.10.2026 строки шли `episodes.sorted { > }` — новые сверху,
    /// а разделитель спрашивал `episodes.last` — последний по ВОЗРАСТАНИЮ,
    /// то есть первую строку списка. Итог: черты не было под первым
    /// эпизодом и была под последним, над кнопкой «Убрать», где своя
    /// черта уже стоит. Вычисляемое `episodes` при этом звалось пять раз
    /// на одну перерисовку — каждый раз проходом по всем эпизодам
    /// хранилища.
    ///
    /// Корзина и «Убрать закончившиеся» стоят за `.editRecords`, «Собаке
    /// лучше — закрыть» — за `.logBasics`: эпизод — объединение записей,
    /// и правило у него то же, что у самих записей. До этой правки
    /// наблюдатель удалял эпизоды наравне с владельцем — экран не
    /// спрашивал прав ни разу.
    private var episodesCard: some View {
        let порядок = episodes.sorted { $0.startedAt > $1.startedAt }
        let закончились = порядок.filter { !$0.isActive() }
        let можноУбирать = appState.can(.editRecords)
        return TGCard {
            TGSectionHeader(title: "эпизоды")
            if порядок.isEmpty {
                TGExplainer(text: "Пока ни одного. Эпизод поднимается сам: два инцидента за сутки или несколько дней подряд с жидким стулом.")
            } else {
                ForEach(порядок) { episode in
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        HStack {
                            Text(episode.title).textStyle(AppFont.bodyEmphasis)
                            Spacer()
                            Text(Fmt.shortDay(episode.startedAt)).textStyle(AppFont.micro)
                            // Эпизод поднимается САМ, по двум инцидентам
                            // за сутки, — и человек не выбирал его заводить.
                            // До 28.09 удалить его было нельзя ничем:
                            // единственный `context.delete(episode)`
                            // в дереве — откат при несохранении.
                            // Заведённое приложением без спроса человек
                            // обязан уметь убрать.
                            if можноУбирать {
                                Button { удаляемый = episode } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: Token.Size.iconSm))
                                        .frame(width: Token.Size.tapTarget,
                                               height: Token.Size.tapTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Token.Status.overdueText)
                                .accessibilityLabel("Удалить эпизод \(episode.title)")
                            }
                        }
                        Text(episode.detail).textStyle(AppFont.caption).wraps()
                        if episode.isActive() { activeEpisodeFooter(episode) }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                    if episode.id != порядок.last?.id { TGDivider() }
                }
                if можноУбирать, закончились.count > 1 {
                    TGDivider()
                    TGButton(title: "Убрать закончившиеся · \(закончились.count)",
                             variant: .destructive, size: .medium,
                             systemImage: "trash") {
                        убратьЗакончившиеся = true
                    }
                }
            }
        }
    }

    /// Эпизоды, которые уже закончились, — и только они.
    ///
    /// **Отзыв 27.10.2026, 21:59: «Добавить функцию удаления или решения
    /// эпизодов».** Обе функции были: корзина у каждой строки с 28.09
    /// (`fd25f88`) и «Собаке лучше — закрыть» у идущего с 26.08
    /// (`5ea2930`). Чего не было — **разом**.
    ///
    /// Замер по `e5dffa8` того же вечера: в архиве, который Виктория
    /// восстановила, лежало **83 эпизода**, и ни один не был обострением
    /// по смыслу — «Пробел в документах» девятнадцать раз, «Щитовидная
    /// железа — забор» восемь, сорок разных заголовков. Семя починено
    /// в сборщике архива; на телефоне они остались, и убрать их можно
    /// было только по одному: 83 эпизода — 166 тапов.
    ///
    /// > **Функция, существующая в единственном числе, при восьмидесяти
    /// > трёх предметах читается как отсутствующая** — и прочиталась
    /// > именно так, человеком, у которого корзина была перед глазами.
    ///
    /// **Идущий эпизод не входит сюда нарочно.** Пока он активен,
    /// вердикт «просится» не считается вовсе (`VerdictEngine:142`),
    /// то есть его удаление меняет поведение главного экрана. У конца
    /// есть своя кнопка, и она говорит, что делает; массовая уборка
    /// такого обещания дать не может.
    ///
    /// Порог `> 1`: ради одной строки второй орган управления рядом
    /// с её же корзиной — это два пути к одному делу, а у Togo записано,
    /// чем они кончаются.
    /// «Показать врачу» прямо из «Истории» — решение Виктории 29.10.2026.
    ///
    /// До этого в «Истории» не было ни одного входа в сводку: она жила
    /// только на «Здоровье», а показывать врачу открывают именно историю.
    /// Экран тот же — `VetSummaryScreen`, второй сборки сводки не заводим.
    /// Право то же, что у вкладки «Здоровье»: сводка — медицинская.
    @ViewBuilder
    private var показатьВрачу: some View {
        if let dog, appState.can(.seeMedical) {
            TGCard(spacing: 0) {
                TGLink(title: "Показать врачу", value: "сводка за период",
                       systemImage: "stethoscope") { VetSummaryScreen(dog: dog) }
            }
            .buttonStyle(.plain)
        }
    }

    private var закончившиеся: [Episode] {
        episodes.filter { !$0.isActive() }
    }

    /// Эпизоды открытой собаки и безымянные (до V10 — общие).
    private var episodes: [Episode] {
        всеЭпизоды.filter { $0.касается(dog) }
    }
}

extension HistoryScreen {
    /// Пока эпизод идёт, вердикт «просится» не считается вовсе — а человек
    /// не видел ни того, что эпизод ещё идёт, ни когда он кончится.
    /// Закрыть его руками было нельзя: метод в модели был, вызывать его
    /// было неоткуда.
    @ViewBuilder
    func activeEpisodeFooter(_ episode: Episode) -> some View {
        Text("Идёт. Закроется сам \(Fmt.shortDay(episode.quietUntil)), если больше ничего не случится.")
            .textStyle(AppFont.micro.color(Token.Status.waitingText))
            .wraps()
        if appState.can(.logBasics) {
            TGButton(title: "Собаке лучше — закрыть", variant: .finish, size: .medium,
                     systemImage: "checkmark") {
                closing = episode
            }
        }
    }

    /// Убрать эпизод целиком.
    ///
    /// Записи не трогаем принципиально: эпизод — это ОБЪЕДИНЕНИЕ
    /// инцидентов, а не они сами. Удалив его вместе с ними, приложение
    /// стёрло бы то, ради чего дневник и ведут.
    ///
    /// `activeEpisode` снимается первым и возвращается при неудаче:
    /// иначе вердикт «просится» остался бы выключенным ссылкой
    /// на эпизод, которого уже нет.
    func удалить(_ episode: Episode) {
        // Кнопку без права не рисуем, но проверка стоит и здесь:
        // подтверждение живёт дольше кнопки, а права могут смениться,
        // пока оно открыто (`AppState.permissions` читается в месте).
        guard appState.can(.editRecords) else {
            Haptics.warning()
            appState.showFailure(Permission.editRecords.отказ)
            удаляемый = nil
            return
        }
        let былоАктивным = appState.activeEpisode?.id == episode.id
        if былоАктивным { appState.activeEpisode = nil }
        context.delete(episode)
        guard context.persist(otherwise: {
            if былоАктивным { appState.activeEpisode = episode }
        }) else {
            // `String(localized:)`: `showFailure` и `showUndo` принимают
            // `String`, и голый литерал рисовался дословно, мимо каталога,
            // — у соседа ниже это было названо, а здесь стояло до 29.10.
            //
            // «Проверь после перезапуска», а не «нажми ещё раз»: откатить
            // `context.delete` нечем, строка из списка уже ушла, и нажать
            // ещё раз не на что. Та же формула, что у `DayOutEditSheet`.
            Haptics.warning()
            appState.showFailure(String(localized: "Не удалилось · проверь после перезапуска"))
            удаляемый = nil
            return
        }
        Haptics.success()
        appState.showUndo(String(localized: "Эпизод удалён · записи остались"))
        удаляемый = nil
    }

    /// Убрать все закончившиеся разом.
    ///
    /// `activeEpisode` не снимаем и не возвращаем: сюда по устройству
    /// `закончившиеся` не попадает активный, а тот, на который указывает
    /// `appState.activeEpisode`, активен по определению. Проверка всё
    /// равно стоит — ссылка живёт отдельно от модели, и расходились они
    /// у Togo уже дважды.
    ///
    /// Счёт берётся ДО удаления: после `context.delete` массив пуст,
    /// и строка подтверждения сказала бы «Убрано 0».
    func убратьВсеЗакончившиеся() {
        guard appState.can(.editRecords) else {
            Haptics.warning()
            appState.showFailure(Permission.editRecords.отказ)
            убратьЗакончившиеся = false
            return
        }
        let кУдалению = закончившиеся.filter { $0.id != appState.activeEpisode?.id }
        guard !кУдалению.isEmpty else {
            убратьЗакончившиеся = false
            return
        }
        let сколько = кУдалению.count
        for episode in кУдалению { context.delete(episode) }
        // `persistNothingToUndo`, а не `persist(otherwise:)`: возвращать
        // нечего — `activeEpisode` сюда не попадает, полей не трогали.
        // Пустые скобки запрещены доком самого `Persist`: забытый возврат
        // от ненужного было бы не отличить.
        guard context.persistNothingToUndo() else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не удалилось · проверь после перезапуска"))
            убратьЗакончившиеся = false
            return
        }
        Haptics.success()
        // `String(localized:)`, а не голый литерал: `showUndo` принимает
        // `String` со значением, и такая строка рисуется дословно, мимо
        // каталога. Соседний `удалить` терял так перевод до 29.10.2026.
        appState.showUndo(String(localized: "Убрано эпизодов: \(сколько) · записи остались"))
        убратьЗакончившиеся = false
    }

    /// Закрыть идущий эпизод.
    ///
    /// До 29.10.2026 отказ сохранения кончался одной вибрацией: эпизод
    /// возвращался в «идёт», подтверждение закрывалось, и человек
    /// не узнавал, что нажатие не состоялось.
    func close(_ episode: Episode) {
        guard appState.can(.logBasics) else {
            Haptics.warning()
            appState.showFailure(Permission.logBasics.отказ)
            closing = nil
            return
        }
        let былЗакрыт = episode.endedAt
        episode.close()
        guard context.persist(otherwise: { episode.endedAt = былЗакрыт }) else {
            Haptics.warning()
            appState.showFailure(String(localized: "Не сохранилось · нажми ещё раз"))
            closing = nil
            return
        }
        Haptics.success()
        closing = nil
        // ЭПИЗОД ЗАКРЫТ — ЗНАЧИТ «КАК ОН СЕЙЧАС?» БОЛЬШЕ НЕ О ЧЁМ.
        //
        // До 04.11.2026 снятия у этого уведомления не было вовсе: его
        // ставили на час вперёд, когда человек выбирал «подожду»,
        // и оно приходило `.timeSensitive` независимо от того, чем
        // кончилось. Эпизод закрыт, врачу позвонили, собаке лучше —
        // а телефон всё равно спрашивал «Как он сейчас?» сквозь
        // «Не беспокоить».
        //
        // Снятие здесь, а не в планировщике: повод знает экран,
        // который закрывает эпизод, и только он.
        Task { await ReminderScheduler.снятьНаблюдение() }
    }
}

/// Обёртка, чтобы дату можно было отдать в `.sheet(item:)`.
private struct DayRef: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Фильтр

nonisolated enum HistoryFilter: String, CaseIterable, Sendable {
    case all, stool, symptoms, reactions, weight

    var title: String {
        switch self {
        case .all: String(localized: "Всё")
        case .stool: String(localized: "Стул")
        // «Инциденты», а не «Симптомы» — решение Виктории 29.10.2026:
        // туалет дома остаётся инцидентом, и чип показывал лужи под
        // словом «симптомы». Полоса под ним всегда звалась «Инциденты».
        case .symptoms: String(localized: "Инциденты")
        case .reactions: String(localized: "Срывы")
        case .weight: String(localized: "Вес")
        }
    }

    /// Фильтр меняет календарь и полосу — одно состояние на экран.
    ///
    /// Список эпизодов фильтр НЕ меняет, и прежняя строка, говорившая
    /// обратное, была ложной в момент записи: `episodesCard` фильтра
    /// не читает (замер 29.10.2026).
    ///
    /// # «Стул» брал выходы БЕЗ стула — починка 29.10.2026
    ///
    /// Стояло `outing && outcome != .urine`. Под это подходили выход
    /// «не сходил» (`.none`) и выход без ответа (`nil`) — у кобеля
    /// это вообще моча по правилу чтения `ToiletClock`. Человек
    /// выбирал «Стул» и видел в календаре дни, где стула не было.
    /// Теперь стул — то же, что считает `ToiletClock.stoolCount`
    /// и `StoolSilence`: запись стула, стул в доме (он инцидент),
    /// выход или остановка в дороге с ответом «стул» / «и то и другое».
    func matches(_ event: LogEvent) -> Bool {
        switch self {
        case .all: true
        case .stool:
            switch event.kind {
            case .stool: true
            case .incident: event.incidentKind == .stoolIndoors
            case .outing, .travelStop: event.outcome == .stool || event.outcome == .both
            default: false
            }
        case .symptoms: event.kind == .incident || event.raisesAlarm
        case .reactions: event.kind == .reaction || event.incidentKind == .reaction
        case .weight: event.kind == .weight
        }
    }

    /// Имя полосы БЕЗ срока: на кадре 10 срок стоит отдельной строкой
    /// справа, а не внутри заголовка.
    ///
    /// `chartTitle`, склеивавший имя со сроком «для озвучки и отчёта»,
    /// снят 29.10.2026: вызовов у него не было ни одного
    /// (`grep -rn chartTitle` — только объявление).
    var chartName: String {
        switch self {
        case .all: String(localized: "Выходы")
        case .stool: String(localized: "Стул")
        case .symptoms: String(localized: "Инциденты")
        case .reactions: String(localized: "Срывы")
        case .weight: String(localized: "Вес")
        }
    }

    var chartExplainer: String {
        switch self {
        case .all: String(localized: "Сколько раз в день выходили. Ровная линия — устоявшийся режим.")
        case .stool: String(localized: "Выше — жиже. Терракотовые столбики — дни с кровью или слизью.")
        case .symptoms: String(localized: "Столбик есть — был инцидент. Пусто — и хорошо.")
        case .reactions: String(localized: "Сколько раз собака срывалась за день. Смотреть надо не на отдельный день, а на то, куда идёт линия за месяц.")
        // Было «Зелёная полоса — коридор, который назвал врач»: полосы
        // не было ни в одной редакции экрана, а коридор показывается
        // строкой «цель … · от врача» (`HistoryScreen.полосаВеса`).
        //
        // Вторая фраза — «сравнивать стоит с собой месяц назад, а не
        // с чужой собакой» — снята 29.10.2026: слово в слово её говорит
        // «как часто гуляете» карточкой ниже, на том же экране.
        case .weight: String(localized: "Взвешивания из «Вес» — за 30 дней, новые сверху.")
        }
    }

    /// Высота столбика у фильтров, которым хватает самих записей.
    ///
    /// `.all` здесь — грубый запасной ответ, а не тот, что рисуется:
    /// выходы считает экран блоками (`HistoryScreen.значение`), потому
    /// что `TimelineBuilder` изолирован главным актором. Запасной
    /// хотя бы не считает отметки внутри прогулки выходами, но выход,
    /// ставший прогулкой, посчитает дважды — **для показа его
    /// не звать**, звать `TimelineBuilder.outingsCount`.
    ///
    /// `.symptoms` считает всё, что фильтр отобрал: день с кровью
    /// в стуле — тревожный, и столбик у него был бы нулевой,
    /// под пояснением «столбик есть — был инцидент».
    func value(for events: [LogEvent]) -> Double {
        switch self {
        case .all: Double(events.filter {
            $0.kind == .walk || ($0.kind == .outing && $0.walkEventID == nil)
        }.count)
        case .stool: events.compactMap { $0.stoolForm?.bristolScore }.map(Double.init).max() ?? 0
        case .symptoms: Double(events.filter(matches).count)
        case .reactions: Double(events.filter { $0.kind == .reaction || $0.incidentKind == .reaction }.count)
        case .weight: 0
        }
    }
}

nonisolated struct HistoryPoint: Identifiable, Sendable {
    let day: Date
    let value: Double
    let isAlarm: Bool
    var id: Date { day }
}

// MARK: - Календарь

/// Месяц с точкой на день. Тап открывает таймлайн этого дня (`DayReadingScreen`).
///
/// Шапка с названием месяца уехала наружу (кадр 10: «ОКТЯБРЬ 2026 Г»
/// прописными **над** карточкой) — здесь осталась только сетка.
struct MonthCalendar: View {
    @Binding var month: Date
    /// Записи, УЖЕ разложенные по дням, — см. `Diary.поДням`.
    ///
    /// Массив здесь был бы честнее по виду и дороже по цене: сетка
    /// спрашивает про сорок два дня, и из массива каждый ответ стоил
    /// бы полного прохода. Индекс строит тот, кто его и так строит
    /// для графика.
    let поДням: [Date: [LogEvent]]
    /// Дни взвешиваний (начала суток) — у фильтра «Вес». Взвешивания
    /// лежат не в ленте, а в `WeightEntry`, и в `поДням` не попадают:
    /// без этого множества календарь под «Весом» был бы пуст всегда.
    var дниВзвешиваний: Set<Date> = []
    var onSelect: (Date) -> Void

    private let calendar = Calendar.current

    /// **Дни недели берутся у локали ЯЗЫКА ПРИЛОЖЕНИЯ, а не русским
    /// списком руками.** Решение Виктории 23.10.2026, прямым словом:
    /// «календарь следует за языком приложения».
    ///
    /// До этого здесь стоял литеральный массив `["пн", "вт", …]`,
    /// и он печатал русские сокращения **на всех пяти языках**.
    /// Поймали кадры витрины: `05-history` на `en-US`, `fr-FR`, `uk`
    /// и `kk` показывал `пн вт ср`.
    ///
    /// > **Строкой в каталоге это не лечится.** Дни недели — не текст
    /// > интерфейса, а формат даты: их даёт система по локали. Ключ
    /// > «пн» в каталоге выглядел бы работой и ничего бы не изменил
    /// > — ровно тот класс, который мы весь день и ловим.
    ///
    /// Язык приложения живёт в `AppleLanguages` (его ставит экран
    /// «Язык»), поэтому берётся `Locale.preferredLanguages.first`,
    /// а не `Locale.current`: человек может выбрать французский
    /// интерфейс при русской системе, и смешанный экран читается
    /// как дефект.
    ///
    /// Порядок остаётся понедельничным намеренно — сетка ниже
    /// (`gridDays`) считает смещение от понедельника, и первый день
    /// недели по локали сдвинул бы подписи относительно чисел.
    /// **Это названное расхождение, а не недосмотр:** в США неделя
    /// начинается с воскресенья, и когда дойдут руки, менять придётся
    /// обе половины разом.
    private var weekdays: [String] {
        let форматтер = DateFormatter()
        форматтер.locale = Locale(identifier: Locale.preferredLanguages.first ?? "ru")
        let короткие = форматтер.shortWeekdaySymbols ?? []
        guard короткие.count == 7 else {
            // Локаль не отдала символы — показываем числа дня недели,
            // а не русский список: молчаливый откат на один язык
            // и есть исходный дефект.
            return (1...7).map(String.init)
        }
        // `shortWeekdaySymbols` начинается с воскресенья; сетка —
        // с понедельника.
        return Array(короткие[1...6]) + [короткие[0]]
    }

    var body: some View {
        TGCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Token.Space.s4), count: 7),
                      spacing: Token.Space.s6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).textStyle(AppFont.micro.color(Token.Ink.secondary))
                }
                ForEach(gridDays, id: \.self) { day in
                    DayCell(day: day, month: month, marker: marker(for: day))
                        .onTapGesture { onSelect(day) }
                }
            }
        }
    }

    /// Сетка всегда начинается с понедельника — чтобы недели не разъезжались.
    private var gridDays: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = calendar.startOfMonth(for: month)
        let weekday = (calendar.component(.weekday, from: first) + 5) % 7
        let leading = (0..<weekday).compactMap { calendar.date(byAdding: .day, value: -(weekday - $0), to: first) }
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        return leading + days
    }

    /// Записи дня берутся из индекса за O(1).
    ///
    /// **Прежде здесь стоял `Diary.onDay(events, day)`, и это главная
    /// найденная причина зависаний 28.10.2026.** Функция зовётся на
    /// КАЖДУЮ ячейку сетки — до сорока двух, — и каждый вызов проходил
    /// весь дневник, сравнивая даты через
    /// `Calendar.isDate(_:inSameDayAs:)`. При тысяче с лишним записей
    /// это десятки тысяч календарных сравнений на одну перерисовку
    /// календаря, то есть на каждое касание фильтра и каждый тик
    /// состояния.
    ///
    /// > Цена росла от ПРОИЗВЕДЕНИЯ записей на дни, а не от записей.
    /// > Поэтому её не было видно, пока дневник вели руками: у человека
    /// > с тремя записями в день календарь стоил столько же, сколько
    /// > у человека с тысячей.
    private func marker(for day: Date) -> DayMarker {
        let начало = calendar.startOfDay(for: day)
        let dayEvents = поДням[начало] ?? []
        if dayEvents.isEmpty { return дниВзвешиваний.contains(начало) ? .ordinary : .none }
        if dayEvents.contains(where: { $0.raisesAlarm || $0.kind == .incident }) { return .alarm }
        if dayEvents.contains(where: { $0.kind.isMedical }) { return .medical }
        return .ordinary
    }
}

nonisolated enum DayMarker: Sendable {
    case none, ordinary, alarm, medical

    /// Значок, а не только цвет.
    ///
    /// Три вида дня отличались ТОЛЬКО оттенком точки в пять пунктов.
    /// Для человека, который не различает красный и зелёный, календарь
    /// был одинаковым насквозь: «найди день, когда была кровь» на нём
    /// не решается вовсе. Форма отвечает на тот же вопрос, не спрашивая
    /// про цвет.
    var symbol: String? {
        switch self {
        case .none: nil
        case .ordinary: "circle.fill"
        case .alarm: "exclamationmark.triangle.fill"
        case .medical: "cross.fill"
        }
    }

    /// Чем день кончился — словами. Идёт в метку озвучки: до этого
    /// метка была датой и только датой, то есть незрячему календарь
    /// не сообщал ничего, кроме чисел месяца.
    var spoken: String? {
        switch self {
        case .none: nil
        case .ordinary: String(localized: "записи есть")
        case .alarm: String(localized: "тревога")
        case .medical: String(localized: "лечение")
        }
    }
}

private struct DayCell: View {
    let day: Date
    let month: Date
    let marker: DayMarker

    /// Значок маркера растёт вместе с системным кеглем.
    ///
    /// Прибитый `size: 8` был бы новым экземпляром того же дефекта,
    /// ради которого в проекте открыт пункт про Dynamic Type — и завела
    /// бы его правка ПРО доступность. `@ScaledMetric` чинит одну точку,
    /// а не весь каталог стилей, но эту точку чинит по-настоящему.
    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 8

    private var isInMonth: Bool { Calendar.current.isDate(day, equalTo: month, toGranularity: .month) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: Token.Space.s2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .textStyle(AppFont.captionEmphasis.color(isInMonth ? Token.Ink.primary : Token.Ink.secondary))
            // 8 пунктов вместо пяти: на пяти форма неразличима,
            // и значок выродился бы обратно в цветную точку.
            Group {
                if let symbol = marker.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: markerSize, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Color.clear
                }
            }
            .frame(height: markerSize + Token.Space.s2)
            .accessibilityHidden(true)
        }
        // Ячейку календаря нажимают пальцем — значит, не меньше 44.
        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
        .background(isToday ? Token.Action.doneQuiet : .clear,
                    in: RoundedRectangle(cornerRadius: Token.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        // Маркер ВХОДИТ в метку. Раньше метка была датой и только датой,
        // и весь смысл дня — тревога, лечение, обычные записи — до озвучки
        // не доезжал: экран «найди день, когда была кровь» был пуст.
        .accessibilityLabel(
            [Fmt.shortDay(day), marker.spoken].compactMap { $0 }.joined(separator: ", ")
        )
        // День открывается нажатием, и сказать об этом должен трейт:
        // `onTapGesture` снаружи ячейки озвучке не виден, и VoiceOver
        // читал «13 сентября, тревога», умалчивая, что сюда можно зайти.
        .accessibilityAddTraits(.isButton)
    }

    private var color: Color {
        switch marker {
        case .none: .clear
        case .ordinary: Token.Action.doneText
        case .alarm: Token.Status.overdueText
        case .medical: Token.Ink.silhouette
        }
    }
}

/// Таймлайн прошедшего дня. Тап по записи открывает её правку.
///
/// # «Режим чтения» был мёртвыми кнопками — починка 29.10.2026
///
/// Здесь стояло `DayTimeline(…) { _ in }`, а `DayTimeline` рисует
/// каждую строку `Button`-ом. Итог: строка нажималась, подсвечивалась,
/// озвучка называла её кнопкой — и не происходило ничего. Поправить
/// вчерашние граммы или убрать запись, сделанную не той собаке,
/// из «Истории» было нельзя, хотя экран выглядел так, будто можно.
///
/// Тап ведёт в тот же `EventEditSheet`, что и на «Сегодня»: права
/// он проверяет сам (без `.editRecords` — плашка права и выключенные
/// поля, то есть то же чтение, только честное), удаление обратимо
/// тостом. Тост рисуется ЗДЕСЬ, сверху: общий `UndoToastView` висит
/// на `RootView` под этой шторкой, и «Отменить» оказалось бы
/// за ней — тот же класс, что у режима прогулки (`WalkMode`).
///
/// # Взвешивания дня
///
/// Под фильтром «Вес» календарь ставит точку на день взвешивания,
/// а взвешивания живут в `WeightEntry`, не в ленте. Без них лист
/// такого дня говорил «записей нет» под точкой, которая говорила
/// обратное.
struct DayReadingScreen: View {
    let day: Date
    let events: [LogEvent]
    var showsAuthor: Bool = false
    /// Взвешивания этого дня — уже отобранные по дню.
    var взвешивания: [WeightEntry] = []

    @State private var правимая: ПравимаяЗапись?

    private var dayEvents: [LogEvent] {
        Diary.onDay(events, day)
    }

    var body: some View {
        let записи = dayEvents
        TGSheet(title: .готовая(Fmt.dayTitle(day)),
                subtitle: записи.isEmpty ? nil : LocalizedStringKey.готовая(Fmt.records(записи.count))) {
            if !взвешивания.isEmpty {
                TGCard {
                    ForEach(взвешивания) { замер in
                        HStack {
                            Text(.готовая(LogKind.weight.title)).textStyle(AppFont.body)
                            Spacer()
                            Text(Fmt.clock(замер.date)).textStyle(AppFont.caption)
                            Text(Fmt.weight(замер.kg)).textStyle(AppFont.numeric(Token.FontSize.meta))
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                    }
                }
            }
            if записи.isEmpty {
                // Под карточкой взвешивания «записей нет» читалось бы
                // как спор с ней: взвешивание и есть запись дня.
                if взвешивания.isEmpty {
                    TGCard { TGExplainer(text: "В этот день записей нет.") }
                }
            } else {
                // Тот же рельс, что и на главном: промежутки между записями
                // в прошлом читают ровно за тем же, зачем и сегодня.
                DayTimeline(events: записи, now: day,
                            showsAuthor: showsAuthor, showsNow: false) { event in
                    правимая = ПравимаяЗапись(id: event.id)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $правимая) { запись in
            EventEditSheet(eventID: запись.id)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Token.Radius.sheet)
        }
        .overlay(alignment: .top) {
            UndoToastView()
                .padding(.top, Token.Space.s8)
        }
    }
}

/// Обёртка, чтобы идентификатор записи можно было отдать в `.sheet(item:)`.
private struct ПравимаяЗапись: Identifiable {
    let id: UUID
}

nonisolated extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
