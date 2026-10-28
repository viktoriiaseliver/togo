import SwiftUI
import SwiftData

/// Здоровье. Вкладка держится правом `.seeMedical`, а не лечением
/// (`RootView`, решение 08.10.2026) — её нет только у помощника.
/// Схему меняет только владелец, остальные видят и исполняют.
///
/// **Переписано под дизайн iOS 28, тема «Кино»** — решение Виктории
/// 22.10.2026. Эталон — `Дизайн/эталонные-кадры/ios28-кино-22.10/11.png`.
///
/// ```
/// было                       стало (кадр 11)
/// шапка-плакат «Здоровье»    фото, кикер «СХЕМА · ЗАПАС · АНАЛИЗЫ»,
///                            заголовок 36 и одна кнопка «…»
/// шестерёнка + «+» в баре    кнопок в шапке нет вовсе; «Настройки» —
///                            пункт меню, «Добавить препарат» — строка
///                            в списке разделов
/// карточка «название/схема»  та же карточка плюс отметки доз чипами
///                            и кнопка «Врач изменил» справа
/// строка «Запас · на N дн.»  своя карточка: срок крупно, «хватит до»,
///                            полоса и белая кнопка «Купил»
/// ```
///
/// **Чего с кадра НЕ взято, и это названо, а не обойдено.** На `11.png`
/// под карточкой лечения стоят три кнопки: «Курс», «Доза ждёт еды»,
/// «Пропуск». Первая сделана (она же «Курс завершён»). Двух других
/// здесь нет: шторки `DoseGateSheet` и `MissedDoseSheet` требуют
/// **конкретную дозу** — `GatedDose` и `MissedDoseTarget`, — а на этом
/// экране дозы в руках нет, она есть на «Сегодня». Кнопка, ведущая
/// в никуда, хуже отсутствующей: механизм без входа у нас уже считают
/// неработающим, а вход без механизма — это отказ, который выглядит
/// нашей виной. Решать, откуда брать дозу, — не правка показа.
struct HealthScreen: View {
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var allMedications: [Medication]
    /// Нужен только для числа в строке справочника. Клиника не
    /// принадлежит собаке — ни связи `dog`, ни обратной у `Dog`, —
    /// поэтому фильтра по активной собаке здесь нет и быть не должно.
    @Query private var клиники: [Clinic]

    @Environment(\.modelContext) private var context
    /// Системный кегль. Читается, а не задаётся: сюда он приезжает
    /// от настройки **процесса**, и на этом же месте его подменяет
    /// аргумент запуска `-UIPreferredContentSizeCategoryName`.
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var editing: Medication?
    @State private var isAdding = false
    @State private var isFinishing = false
    @State private var changingSchedule: Medication?
    @State private var countingPills: Medication?
    /// Настройки открываются из меню «…». Переход делает хозяин экрана:
    /// `NavigationLink` внутри `Menu` срабатывает непредсказуемо
    /// (разбор у `HeaderMenu`).
    @State private var показатьНастройки = false

    private var dog: Dog? { appState.activeDog(from: dogs) }

    private var medications: [Medication] {
        guard let dog else { return [] }
        // Надгробия мимо: `@Query` отдаёт все схемы базы, то есть этот
        // вход идёт мимо фильтра у `dog.medications`.
        return allMedications.filter {
            $0.dog?.persistentModelID == dog.persistentModelID && $0.deletedAt == nil
        }
    }

    /// То, что собака пьёт СЕЙЧАС.
    ///
    /// **Отменённое отсюда убрано 27.10.2026 по просьбе Виктории:**
    /// «неактивные таблетки лучше скрыть в архив, чтобы не путать
    /// пользователей». Повод прямой — в восстановленной карте Стича
    /// девять схем, из них действует ОДНА, а остальные восемь шли
    /// следом в том же списке, и у каждой своя карточка запаса.
    ///
    /// > Отменённая схема и действующая выглядят одинаково, а значат
    /// > противоположное. На экране, где сверяют дозу, это хуже, чем
    /// > отсутствие истории.
    ///
    /// Удалять их нельзя: история лечения — то, что спрашивает врач
    /// первым («чем лечили раньше и чем кончилось»). Поэтому они
    /// не исчезают, а уходят в свёрнутый раздел ниже.
    private var действующиеСхемы: [Medication] {
        medications.filter { $0.cancelledAt == nil }
    }

    /// История: отменённые схемы, новые сверху.
    private var прошлыеСхемы: [Medication] {
        medications.filter { $0.cancelledAt != nil }
            .sorted { ($0.cancelledAt ?? .distantPast) > ($1.cancelledAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            КиноЭкран(экран: .health,
                      кикер: "Схема · Запас · Анализы",
                      заголовок: "Здоровье",
                      настройки: { показатьНастройки = true }) {
                // **Говорим, что он только смотрит, — до первого отказа.**
                //
                // Без этой строки человек без права `editTreatment` видел
                // схему лечения, жал «Врач изменил» или строку препарата
                // и получал тишину: `.disabled(!canEdit)` молчит
                // по устройству.
                //
                // Правило дизайна круга 5: выключенный орган допустим,
                // только если рядом словом сказано, чего не хватает.
                // Разбор и причина одного типа на все экраны —
                // `ПлашкаПрава`.
                //
                // > **Отказ, о котором сказали заранее, — это граница.
                // > Отказ, о котором сказали после нажатия, — это наша
                // > поломка в глазах человека.**
                //
                // **ТРИ РУКОПИСНЫЕ КОПИИ СВЕДЕНЫ К ОДНОЙ, 26.10.2026.**
                // Одно утверждение об отказе жило здесь тремя
                // независимыми редакциями, и ни одна не читала
                // `Permission.отказ`:
                //
                // ```
                // :82  TGBanner    title: "Схему меняет владелец"  ЗАХАРДКОЖЕН
                // :194 TGExplainer "Схему меняет владелец. Ты видишь
                //                   её и отмечаешь приёмы."        ТРЕТЬЯ ФОРМУЛИРОВКА
                // Permission.отказ "Схему меняет владелец"         ИСТОЧНИК, не читался
                // ```
                //
                // `FamilyResolver.swift:273-277` называет этот класс
                // вслух: «одно правило жило двумя проверками
                // и разошлось в краю». Здесь оно жило ТРЕМЯ показами
                // и уже разошлось: подзаголовок звал право «Менять
                // схему лечения», а в «Семье» человек ищет его
                // по `Permission.title` — совпало случайно, и следующая
                // правка любой из трёх копий совпадение бы сняла.
                //
                // Цена копии измерена не здесь: `QuotedNamesTests` ловил
                // ровно это трижды за сутки 25.10.2026.
                if !canEdit { ПлашкаПрава(право: .editTreatment) }
                if действующиеСхемы.isEmpty && прошлыеСхемы.isEmpty {
                    EmptyStateCard(
                        subject: .health,
                        title: "Схемы лечения пока нет",
                        message: "Добавь препарат — приложение начнёт напоминать про дозу, держать окно натощак и защищать от двойной дозы. Это бесплатно и работает всегда.",
                        actionTitle: canEdit ? "Добавить препарат" : nil,
                        action: canEdit ? { isAdding = true } : nil
                    )
                } else {
                    ForEach(действующиеСхемы) { medication in
                        карточкаЛечения(medication)
                        карточкаЗапаса(medication)
                    }
                    прошлыеСхемыРаздел
                }

                показательКарточка
                sectionsGrid
                finishCourse
                disclaimer
            }
            .usageScreen(.health)
            .navigationDestination(isPresented: $показатьНастройки) {
                SettingsScreen()
            }
            .sheet(isPresented: $isAdding) { MedicationEditorSheet(dog: dog) }
            .sheet(item: $editing) { medication in
                MedicationEditorSheet(medication: medication, dog: dog)
            }
            .sheet(item: $changingSchedule) { medication in
                ScheduleChangeSheet(medication: medication)
            }
            .sheet(item: $countingPills) { medication in
                PillSupplyScreen(medication: medication, courseEnds: medication.courseEnd)
            }
            .sheet(isPresented: $isFinishing) {
                if let dog {
                    CourseFinishSheet(
                        dog: dog,
                        summary: TreatmentCourse.summary(dog),
                        farewell: TreatmentCourse.farewell(dog),
                        onFinish: { finish() },
                        onScheduleCheckup: { days in
                            TreatmentCourse.scheduleCheckup(for: dog, after: days, context: context)
                        }
                    )
                }
            }
        }
    }

    /// Прошлые схемы — свёрнуто, и число в заголовке.
    ///
    /// Свёрнуто потому, что это СПРАВКА, а не рабочий список: сюда
    /// заглядывают, когда врач спрашивает «чем лечили раньше».
    /// Число в заголовке нужно, чтобы раздел не читался как пустой —
    /// закрытая полка без счёта выглядит так же, как полка, на которой
    /// ничего нет.
    ///
    /// Карточки запаса у прошлых схем НЕТ: запас отвечает на вопрос
    /// «когда покупать», а у отменённой схемы покупать нечего, и число
    /// в ней осталось бы от последнего дня приёма — то есть врало бы
    /// про сегодня.
    @ViewBuilder
    private var прошлыеСхемыРаздел: some View {
        if !прошлыеСхемы.isEmpty {
            TGCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Token.Space.s12) {
                        ForEach(прошлыеСхемы) { схема in
                            строкаПрошлойСхемы(схема)
                        }
                    }
                    .padding(.top, Token.Space.s8)
                } label: {
                    TGSectionHeader(title: .готовая(
                        String(localized: "Прошлые схемы · \(прошлыеСхемы.count)")))
                }
                .tint(Token.Ink.secondary)
            }
        }
    }

    /// Строка истории: чем лечили, когда отменили и почему.
    private func строкаПрошлойСхемы(_ схема: Medication) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(.готовая(схема.name))
                .textStyle(AppFont.bodyEmphasis)
                .wraps()
            Text(.готовая(подписьПрошлой(схема)))
                .textStyle(AppFont.caption)
                .foregroundStyle(Token.Ink.secondary)
                .wraps()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «1 таблетка · до 26.10.2026 · повод отмены».
    ///
    /// Повод берётся из `cancelledNote` и НЕ придумывается: пустая
    /// заметка значит «причину не записали», и дописать её за человека
    /// значило бы сочинить историю лечения.
    private func подписьПрошлой(_ схема: Medication) -> String {
        var части: [String] = []
        if let доза = Fmt.notBlank(схема.doseText) { части.append(доза) }
        if let до = схема.cancelledAt {
            части.append(String(localized: "до \(Fmt.shortDay(до))"))
        }
        if let повод = Fmt.notBlank(схема.cancelledNote ?? "") {
            части.append(повод)
        }
        return части.joined(separator: " · ")
    }

    /// Схему меняет только владелец. Остальные видят её и отмечают приёмы.
    private var canEdit: Bool { appState.can(.editTreatment) }

    /// Карточка лечения по кадру 11: название и доза крупно, схема
    /// подписью, «Врач изменил» справа, отметки доз чипами, «Курс» внизу.
    ///
    /// Два действия, ради которых чаще всего и открывают препарат:
    /// врач поменял схему и таблетки кончаются. Оба лежали глубоко
    /// в форме правки — то есть их не было.
    @ViewBuilder
    private func карточкаЛечения(_ medication: Medication) -> some View {
        TGCard {
            // **На крупном кегле ряд становится столбцом, и это
            // медицинский экран, а не косметика.** Кадр 25.10.2026
            // (`до-правки/04-здоровье-ax5.png`, `AccessibilityXXXL`):
            // чип «Врач изменил» — это `Capsule` с `minHeight: 44`
            // и текстом под `.wraps()`. Текст в нём встаёт в три
            // строки, капсула вырастает до почти круга, и своей
            // идеальной шириной съедает две трети ряда. Название
            // препарата остаётся в трети и ломается ПОСРЕДИ СЛОВА:
            // «Левот / ирокс / ин ½ / табле / тки».
            //
            // Человек открывает этот экран, чтобы прочитать, какое
            // лекарство давать. «Левотироксин», разорванный на пять
            // огрызков рядом с кругом, — это не теснота оформления:
            // название читается по буквам или не читается вовсе.
            //
            // Ширины тут не хватает ПО УСТРОЙСТВУ: два слова чипа
            // кеглем под сорок плюс название препарата в одну строку
            // в четырёхстах точках не помещаются. Поэтому столбцом —
            // той же формой, которой это уже решено у соседей
            // (`TodayBottom:53`, `FamilyScreen.dutyCard:326`,
            // `WalkMode` после `78c5425`).
            //
            // Раскладка выбирается явным `if`, а не `ViewThatFits`:
            // он в проекте запрещён — держал в дереве обе ветки,
            // и озвучка находила два одинаковых органа.
            Group {
                if размерТекста.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Token.Space.s8) {
                        названиеИСхема(medication)
                        чипВрачИзменил(medication)
                    }
                } else {
                    HStack(alignment: .top, spacing: Token.Space.s12) {
                        названиеИСхема(medication)
                        чипВрачИзменил(medication)
                    }
                }
            }

            отметкиДоз(medication)

            if let note = medication.cancelledNote {
                TGDivider()
                Text(verbatim: note).textStyle(AppFont.caption).wraps()
            }
            // **Третьей копии отказа здесь НЕТ, и это снятие, а не
            // пропуск.** Тут стоял `TGExplainer` со своей, третьей
            // формулировкой — «Схему меняет владелец. Ты видишь её
            // и отмечаешь приёмы.» — и печатался он НА КАЖДОЙ карточке
            // препарата: при трёх препаратах человек читал один и тот
            // же отказ четыре раза (плашка сверху плюс три карточки).
            //
            // Отказ назван один раз, `ПлашкаПрава` вверху экрана,
            // и этого довольно: она стоит выше карточек, то есть
            // человек читает её ПРЕЖДЕ, чем дойдёт до выключенной
            // строки. Повтор у каждого органа — не забота, а шум,
            // в котором граница перестаёт читаться как граница.
        }
    }

    /// Название, доза и схема. Вынесено из `карточкаЛечения`, чтобы
    /// у двух раскладок были **буквально одни и те же дети**: разойдись
    /// они — и ветка, которую реже видят, тихо отстанет.
    @ViewBuilder
    private func названиеИСхема(_ medication: Medication) -> some View {
        Button { if canEdit { editing = medication } } label: {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(verbatim: "\(medication.name) \(medication.doseText)")
                    .textStyle(AppFont.cardTitle)
                    .wraps()
                Text(verbatim: medication.scheduleSummary)
                    .textStyle(AppFont.caption)
                    .wraps()
                // Дата начала — только названная (V8). Первую дозу журнала
                // за начало здесь не выдаём: это догадка, а карточку
                // читает врач.
                if let начало = medication.startedAt {
                    Text(.готовая(String(localized: "с \(Fmt.shortDay(начало))")))
                        .textStyle(AppFont.caption.color(Token.Ink.secondary))
                }
                if medication.isPaused {
                    Text("на паузе")
                        .textStyle(AppFont.micro.color(Token.Status.waitingText))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
    }

    @ViewBuilder
    private func чипВрачИзменил(_ medication: Medication) -> some View {
        if canEdit {
            КиноЧип(подпись: "Врач изменил") { changingSchedule = medication }
        }
    }

    /// Отметки доз за сегодня — чипами, как на кадре 11: «✓ 8:00 · дал»
    /// и «20:00».
    ///
    /// **Это отметка, а не кнопка, и нажатия у неё нет нарочно.** Дозу
    /// отмечают на «Сегодня», где рядом стоят окно натощак, защита
    /// от двойной дозы и «беру на себя». Вторая поверхность отметки
    /// завела бы вторую реализацию тех же ворот — у Того это уже
    /// стоило трёх молчавших реализаций правила «не кормить».
    @ViewBuilder
    private func отметкиДоз(_ medication: Medication) -> some View {
        let слоты = medication.schedule
        if !слоты.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Token.Space.s8) {
                    ForEach(слоты, id: \.minuteOfDay) { слот in
                        let дано = датьВремя(medication, слот.minuteOfDay)
                        КиноЧип(подпись: .готовая(подписьДозы(слот, дано: дано)),
                                значок: дано == nil ? "clock" : "checkmark",
                                выбран: дано != nil)
                    }
                }
                .padding(.vertical, Token.Space.s2)
            }
        }
    }

    /// Когда дозу этого часа отметили сегодня. Пусто — ещё не отмечена.
    private func датьВремя(_ medication: Medication, _ минута: Int) -> Date? {
        let календарь = Calendar.current
        return medication.doses.first { запись in
            guard запись.isGiven, календарь.isDateInToday(запись.scheduledAt) else { return false }
            let час = календарь.component(.hour, from: запись.scheduledAt)
            let мин = календарь.component(.minute, from: запись.scheduledAt)
            return час * 60 + мин == минута
        }?.givenAt
    }

    /// «8:00 · дал» либо просто «20:00». Разделитель точкой, а не
    /// грамматикой: склейки фраз хендофф переносить запрещает.
    private func подписьДозы(_ слот: DoseSlot, дано: Date?) -> String {
        дано == nil
            ? слот.clock
            : [слот.clock, String(localized: "дал")].joined(separator: " · ")
    }

    /// Карточка запаса по кадру 11: срок крупно, «хватит до» тем же
    /// цветом, полоса и белая кнопка «Купил».
    ///
    /// Кнопка ведёт в `PillSupplyScreen` — туда, где лежит «новая пачка».
    /// Второго писателя остатка не заводим: у `PillSupplyScreen` прямо
    /// записано, что размер упаковки поднимает только он, и повторить
    /// это здесь значило бы развести две арифметики запаса.
    @ViewBuilder
    private func карточкаЗапаса(_ medication: Medication) -> some View {
        if let запас = supply(medication) {
            let уровень = PillSupplyAdvisor.level(запас)
            let цвет = уровень == .ok ? Token.Ink.primary : уровень.цветТекста
            TGCard {
                TGSectionHeader(title: .готовая(
                    [String(localized: "запас"), medication.name].joined(separator: " · ")))
                Text(verbatim: Fmt.days(запас.days))
                    .textStyle(TextStyleToken(size: КиноРазмеры.метрика,
                                              weight: Token.FontWeight.light,
                                              color: цвет,
                                              monospacedDigits: true,
                                              relativeTo: .title2))
                    .wraps()
                if let последний = запас.lastDay {
                    Text("хватит до \(Fmt.shortDay(последний))")
                        .textStyle(AppFont.captionEmphasis.color(цвет))
                        .wraps()
                }
                if let нехватка = запас.shortfallDays, let конец = medication.courseEnd {
                    Text("Курс идёт до \(Fmt.shortDay(конец)) — не хватит \(Fmt.days(нехватка)). Аптеки везут 2–3 дня.")
                        .textStyle(AppFont.caption.color(цвет))
                        .wraps()
                }
                КиноПолосаЗапаса(доля: запас.packSize > 0 ? запас.remaining / запас.packSize : 0,
                                 цвет: цвет)
                остаток(запас)
                // **«Курс кончится раньше — не покупать».** Правило
                // записано в `DECISIONS.md` и живёт в `courseEndsFirst`;
                // без этой ветки кнопка «Купил» звала бы в аптеку
                // за препаратом, который завтра отменят.
                if запас.courseEndsFirst {
                    TGExplainer(text: "Курс кончится раньше запаса — покупать не надо.")
                } else if canEdit {
                    TGButton(title: "Купил", systemImage: "bag") {
                        countingPills = medication
                    }
                }
            }
        } else if canEdit {
            TGCard {
                TGSectionHeader(title: .готовая(
                    [String(localized: "запас"), medication.name].joined(separator: " · ")))
                TGExplainer(text: "Счёт не включён. Скажи, сколько таблеток в пачке — дальше приложение вычитает по одной с каждой отметки и предупредит за три дня до конца.")
                TGButton(title: "Включить счёт", variant: .secondary, size: .medium) {
                    countingPills = medication
                }
            }
        }
    }

    /// «11 из 30» — целыми числами и **теми же двумя ключами, что
    /// в шторке запаса**.
    ///
    /// Один склеенный ключ `«N из M»` был бы новым: в каталоге его нет,
    /// и у француза он откатился бы на русское «из». Числа целые
    /// по той же причине, что в `PillSupplyScreen`: ключи счётных строк
    /// стоят на `%lld`, дробь завела бы новые ключи с пустыми
    /// переводами на четырёх языках.
    @ViewBuilder
    private func остаток(_ запас: PillSupply) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s6) {
            Text(verbatim: "\(Int(запас.remaining.rounded(.down)))")
                .textStyle(AppFont.captionEmphasis)
            Text("из \(Int(запас.packSize.rounded(.down)))")
                .textStyle(AppFont.caption)
        }
    }

    /// Курс передаётся обоим местам, а не одному.
    ///
    /// `shortfallDays` считал верно и был покрыт тестами, но живьём
    /// не срабатывал ни разу: тесты передавали дату аргументом сами,
    /// а экран передать её не мог — поля у препарата не было. Строка
    /// «Курс идёт до … — не хватит …» не показывалась никому.
    ///
    /// Расход — СУММА доз (`dailyUse`), а не число приёмов.
    ///
    /// Полтаблетки дважды в день уходят по одной таблетке в сутки,
    /// а не по две. Прежний `max(1, times.count)` ошибался бы в сторону
    /// «хватит дольше» — человек не купил бы вовремя, ровно тот случай,
    /// ради которого счётчик и завели. Пока в `doseSlotsData` не писал
    /// ни один экран, числа совпадали; первая записанная половинка
    /// включила бы ошибку молча.
    ///
    /// **Отсюда же `nil` у препарата без расписания.** Пустое `schedule`
    /// даёт нулевой расход, и запас честно отвечает «не считаем» вместо
    /// прежней единицы в день. Выдумывать расход там, где схемы нет,
    /// значит называть срок, которого никто не назначал.
    private func supply(_ medication: Medication) -> PillSupply? {
        PillSupplyAdvisor.supply(remaining: medication.remaining,
                                 packSize: medication.packSize,
                                 perDay: medication.dailyUse,
                                 courseEnds: medication.courseEnd)
    }

    // MARK: Показатель

    /// Карточка последнего показателя — кадр 11, «Т4 · протокол контроля»
    /// с нормой справа, и кадр 14, где тот же блок стоит крупно.
    ///
    /// **Нормы приложение не придумывает.** `referenceLow` / `referenceHigh`
    /// приходят с бланка; нет их — строка про норму не печатается вовсе.
    /// «Норма не указана» и «в норме» — разные новости, и вторую
    /// приложение сказать не может.
    ///
    /// **Число показывается `ЧислоСБланка.показать`, а не `Fmt.decimal`.**
    /// Округление до одного знака писано для веса: `16,75 нмоль/л`
    /// как `16,8` — потеря данных в медицинском числе.
    @ViewBuilder
    private var показательКарточка: some View {
        if let dog, let последний = последнийПоказатель(dog) {
            NavigationLink { LabChartScreen(dog: dog) } label: {
                TGCard {
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(verbatim: Fmt.notBlank(последний.indicator)
                             ?? String(localized: "показатель")).textStyle(AppFont.cardTitle).wraps()
                        Spacer(minLength: Token.Space.s8)
                        if let норма = нормаСтрокой(последний) {
                            Text(verbatim: норма).textStyle(AppFont.caption).wraps()
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                        Text(verbatim: ЧислоСБланка.показать(последний.value ?? 0))
                            .textStyle(TextStyleToken(size: КиноРазмеры.метрика,
                                                      weight: Token.FontWeight.light,
                                                      color: Token.Ink.link,
                                                      monospacedDigits: true,
                                                      relativeTo: .title2))
                            .wraps()
                        if let единица = Fmt.notBlank(последний.unit) {
                            Text(verbatim: единица)
                                .textStyle(AppFont.bodyEmphasis.color(Token.Ink.link))
                                .wraps()
                        }
                    }
                    КиноСтолбики(значения: рядПоказателя(dog, like: последний))
                    Text("Смотреть надо не на одно число, а на то, куда идёт ряд. Открой график.")
                        .textStyle(AppFont.caption)
                        .wraps()
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Последний анализ с ЧИСЛОМ. Предел прибора (`<0,1`) сюда
    /// не попадает нарочно: его нельзя нарисовать столбиком, не превратив
    /// «меньше, чем прибор различает» в число.
    private func последнийПоказатель(_ dog: Dog) -> LabResult? {
        dog.labResults
            .filter { $0.value != nil }
            .max { $0.sampledOn < $1.sampledOn }
    }

    /// Ряд того же показателя по датам — для полосы столбиков.
    private func рядПоказателя(_ dog: Dog, like образец: LabResult) -> [Double] {
        dog.labResults
            .filter { $0.indicator == образец.indicator && $0.value != nil }
            .sorted { $0.sampledOn < $1.sampledOn }
            .suffix(КиноРазмеры.днейВПолосе)
            .compactMap(\.value)
    }

    /// «норма 1,0–4,5» с бланка. Пусто — нормы на бланке не было.
    private func нормаСтрокой(_ анализ: LabResult) -> String? {
        guard let низ = анализ.referenceLow, let верх = анализ.referenceHigh else { return nil }
        return String(localized: "норма \(ЧислоСБланка.показать(низ))–\(ЧислоСБланка.показать(верх))")
    }

    /// Курс кончается здесь, а не тумблером в профиле, где его никто
    /// не найдёт. Вкладка при этом НЕ уходит: с 08.10.2026 (`02c1e88`) её держит
    /// право `.seeMedical`, а не курс, — иначе она исчезала ровно в день, когда
    /// нужен отчёт врачу.
    @ViewBuilder
    private var finishCourse: some View {
        if canEdit, dog != nil {
            Button { isFinishing = true } label: {
                TGCard {
                    TGListRow(title: "Курс завершён", systemImage: "checkmark.seal")
                    TGExplainer(text: "Записи останутся в истории и в отчёте врачу. Вернуть курс можно в профиле.")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func finish() {
        guard let dog else { return }
        TreatmentCourse.finish(dog, by: appState.currentUserName, context: context)
        appState.showUndo("Курс завершён")
        Haptics.success()
    }

    /// Сколько анализов у собаки — в строке раздела, а не внутри него.
    /// Пусто, когда ни одного: «0» рядом с названием читается как
    /// неисправность, а отсутствие числа — как «ещё не заводили».
    private var анализовВсего: LocalizedStringKey? {
        guard let dog, !dog.labResults.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.labResults.count))
    }

    /// Пусто, пока рисовать нечего: строка «График показателя» без
    /// данных ведёт на «Рисовать пока нечего», и подпись об этом
    /// честнее, чем молчание.
    private var графикДоступен: LocalizedStringKey? {
        guard let dog else { return nil }
        let сЧислом = dog.labResults.filter { $0.value != nil }.count
        return сЧислом >= 2 ? .готовая(Fmt.records(сЧислом)) : nil
    }

    private var визитовВсего: LocalizedStringKey? {
        guard let dog, !dog.vetVisits.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.vetVisits.count))
    }

    private var диагнозовВсего: LocalizedStringKey? {
        guard let dog, !dog.diagnoses.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.diagnoses.count))
    }

    private var назначенийВсего: LocalizedStringKey? {
        guard let dog, !dog.prescriptions.isEmpty else { return nil }
        return .готовая(Fmt.records(dog.prescriptions.count))
    }

    /// Сколько организаций в справочнике. Надгробия не считаются:
    /// `ОбщееУдаление` — «надгробие, которое видно человеку, —
    /// не удаление, а порча экрана», и число тут такой же показ,
    /// как список.
    private var клиникВсего: LocalizedStringKey? {
        let живые = клиники.filter { $0.deletedAt == nil }
        guard !живые.isEmpty else { return nil }
        return .готовая(Fmt.records(живые.count))
    }

    private var sectionsGrid: some View {
        TGCard(spacing: 0) {
            // **ВХОД ВЗАМЕН «+» В ШАПКЕ.** Кадр 11 не даёт в шапке
            // ни одной кнопки, кроме «…», — и вместе с «+» исчезал
            // единственный способ завести ВТОРОЙ препарат: пустое
            // состояние со своей кнопкой показывается только пока
            // препаратов ноль. Убрать кнопку, не переселив вход, значило
            // бы сделать то, что у нас называется «механизм без входа».
            if canEdit, dog != nil {
                Button { isAdding = true } label: {
                    TGListRow(title: "Добавить препарат", systemImage: "plus")
                }
                .buttonStyle(.plain)
                TGDivider()
            }
                        TGLink(title: "Протокол контроля", value: "T0 / +4 / +6", systemImage: "timer") { ProtocolScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Вес и симптомы", value: dog.map { .готовая(Fmt.weight($0.weightKg)) }, systemImage: "scalemass") { WeightScreen(dog: dog) }
            TGDivider()
            // МЕСТО ВЫЗОВА. Без этой строки экран анализов существует
            // и недостижим: до 08.10.2026 `LabResult` создавался только
            // в `MedicalRecordGallery`, а она целиком под `#if DEBUG`.
            // Модель, обмен, архив и карточки были, а человек не мог
            // завести ни одной записи — то есть поверхность была
            // подключена на ноль мест. Сторож на эту строку —
            // `ДорогаКАнализамTests`, от запрета.
                        TGLink(title: "Анализы", value: анализовВсего, systemImage: "testtube.2") { LabResultsScreen(dog: dog) }
            TGDivider()
            // МЕСТО ВЫЗОВА графика. Без него экран существует
            // и недостижим — то состояние, в котором весь медслой
            // пролежал до 08.10.2026.
                        TGLink(title: "График показателя", value: графикДоступен, systemImage: "chart.xyaxis.line") { LabChartScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Визиты к врачу", value: визитовВсего, systemImage: "stethoscope") { VetVisitsScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Диагнозы", value: диагнозовВсего, systemImage: "questionmark.circle") { DiagnosesScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Назначения", value: назначенийВсего, systemImage: "doc.text") { PrescriptionsScreen(dog: dog) }
            TGDivider()
                        // «Визиты к врачу» — строкой выше, своим экраном. Здесь был второй
                        // вход «Прививки и визиты», и вёл он в ВЕСЬ уход — зубы, уши,
                        // когти (отзыв 27.10: «Почему в прививках и визитах уход?»).
                        TGLink(title: "Прививки", systemImage: "syringe") { CareScreen(dog: dog, только: .medical) }
            TGDivider()
            // МЕСТО ВЫЗОВА справочника клиник. Без этой строки `Clinic`
            // существует и недостижим: у модели НЕ БЫЛО НИ ОДНОГО
            // человеческого места создания (замер 26.10.2026) —
            // приём извне, откат архива, маркер схемы и галерея
            // под `#if DEBUG`. При этом `VetVisitEditor`
            // и `PrescriptionEditor` уже рисовали `Picker("Клиника")`,
            // и у человека там навсегда стояла одна строка
            // «не указана».
            //
            // Это та же семья, что `LabResult` до 08.10.2026, и хуже
            // её на один шаг: там экран был недостижим, здесь ДВА
            // экрана спрашивали то, на что ответить нельзя.
            // Сторож на эту строку — `ДорогаКСправочникуКлиникTests`,
            // от запрета, по образцу `ДорогаКАнализамTests`.
                        TGLink(title: "Клиники и лаборатории", value: клиникВсего, systemImage: "cross.case") { ClinicsScreen() }
            TGDivider()
                        TGLink(title: "Сводка врачу", value: "разворот за минуту", systemImage: "doc.text") { VetSummaryScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Выгрузка записей", systemImage: "tablecells") { VetReportScreen(dog: dog) }
            TGDivider()
                        TGLink(title: "Подготовка к процедурам", systemImage: "hand.raised") { ProcedurePrepScreen() }
        }
        .buttonStyle(.plain)
    }

    /// Дисклеймер лежит здесь, а не в настройках: его читают там, где медицина.
    private var disclaimer: some View {
        NavigationLink { MedicalDisclaimerScreen() } label: {
            TGCard {
                Text("Приложение помогает вести записи и не является медицинским устройством. Диагнозов не ставит, дозировок не назначает.")
                    .textStyle(AppFont.caption)
                Text("Подробнее").textStyle(AppFont.captionEmphasis.color(Token.Action.doneText))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Полоса запаса по кадру 11: четырнадцать отрезков, залитых
/// пропорционально остатку.
///
/// **Отрезки — это способ нарисовать долю, а не единица измерения.**
/// Их всегда четырнадцать, сколько бы таблеток ни было в пачке:
/// тридцать отрезков на тридцать таблеток слиплись бы в сплошную
/// полосу, а «сколько штук» говорит строка под ней. Если однажды
/// отрезок захотят читать как таблетку — это другая величина, и она
/// требует другого имени, а не правки этого вида.
private struct КиноПолосаЗапаса: View {
    /// Сколько осталось от пачки, 0…1.
    let доля: Double
    let цвет: Color

    private var залито: Int {
        let целых = (Double(КиноРазмеры.днейВПолосе) * max(0, min(1, доля))).rounded()
        // Пока осталась хоть капля, хотя бы один отрезок горит: ноль
        // отрезков при ненулевом остатке читается как «кончилось».
        return доля > 0 ? max(1, Int(целых)) : 0
    }

    var body: some View {
        HStack(spacing: Token.Space.s4) {
            ForEach(0..<КиноРазмеры.днейВПолосе, id: \.self) { номер in
                Capsule()
                    .fill(номер < залито ? цвет : Token.Surface.raised)
                    .frame(height: КиноРазмеры.минимумСтолбика * 2)
            }
        }
        // Долю голосом читает строка остатка, стоящая рядом: «11 из 30»
        // точнее, чем «полоса заполнена на треть».
        .accessibilityHidden(true)
    }
}

/// Протокол контроля. Стартует от фактической отметки дозы и считает интервал сам —
/// именно отсутствие строки «доза → забор» дважды приводило к неверному чтению анализов.
struct ProtocolScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var lastDose: DoseRecord? {
        dog?.medications.flatMap(\.doses)
            .filter(\.isGiven)
            .max { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Протокол", отступы: false)
            if let dose = lastDose, let givenAt = dose.givenAt {
                TGCard {
                    Text("T+\(Fmt.duration(now.timeIntervalSince(givenAt)))").textStyle(AppFont.display)
                    Text("Доза дана в \(Fmt.clock(givenAt)) под наблюдением").textStyle(AppFont.caption)
                }
                TGCard(spacing: 0) {
                    ProtocolRow(label: "T0", time: givenAt,
                                title: "доза \(dog?.medications.first?.doseText ?? "")",
                                detail: "отмечено с точностью до минуты", isDone: true)
                    TGDivider()
                    ProtocolRow(label: "+4", time: givenAt.addingTimeInterval(4 * 3600),
                                title: "забор крови", detail: "напомним за 30 минут",
                                isDone: now > givenAt.addingTimeInterval(4 * 3600))
                    TGDivider()
                    ProtocolRow(label: "+6", time: givenAt.addingTimeInterval(6 * 3600),
                                title: "забор крови", detail: "вторая точка, по назначению",
                                isDone: now > givenAt.addingTimeInterval(6 * 3600))
                }
                TGCard {
                    Text("Интервал посчитаем сами").textStyle(AppFont.cardTitle)
                    Text("В отчёте будет строка «доза → забор: \(Fmt.duration(now.timeIntervalSince(givenAt)))». Без этой строки анализы уже дважды читали неверно.")
                        .textStyle(AppFont.caption)
                }
                TGButton(title: "Отметить забор крови", systemImage: "cross.vial") {
                    recordDraw()
                }
            } else {
                TGCard {
                    Text("Протокол начинается с дозы").textStyle(AppFont.cardTitle)
                    Text("Отметь приём препарата — приложение засечёт время и само посчитает +4 и +6 часов.")
                        .textStyle(AppFont.caption)
                }
            }
        }
        .navigationTitle("Протокол")
        .cinemaScreen(экран: .sub("protocol"))
        .onReceive(tick) { now = $0 }
    }

    private func recordDraw() {
        EventLog(context: context, appState: appState)
            .record(.note, dog: dog, confirmation: "Записано · забор крови") { event in
                // Через каталог: заметку человек читает в ленте дня
                // и в сводке врачу. `note` — `String`, присвоение
                // литерала каталог не спрашивает, и у француза
                // в собственном дневнике встало бы русское слово.
                event.note = String(localized: "Забор крови")
            }
    }
}

private struct ProtocolRow: View {
    let label: String
    let time: Date
    let title: String
    let detail: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Text(label)
                .textStyle(AppFont.numeric(15))
                .fixedSize()
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("\(Fmt.clock(time)) · \(title)").textStyle(AppFont.bodyEmphasis)
                Text(detail).textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Token.Action.doneText : Token.Ink.secondary)
        }
        .padding(.vertical, Token.Space.s10)
    }
}

/// Отчёт врачу собирается из уже записанного: нет ни одного поля
/// «заполните для врача».
struct VetReportScreen: View {
    let dog: Dog?

    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date()
    @State private var language = "RU"

    private var events: [LogEvent] {
        Diary.active(dog?.events ?? []).filter { $0.date >= from && $0.date <= to }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Отчёт", отступы: false)
            TGCard(spacing: 0) {
                DatePicker("С", selection: $from, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                DatePicker("По", selection: $to, in: from..., displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                Picker("Язык", selection: $language) {
                    ForEach(["RU", "FR", "EN"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, Token.Space.s8)
            }

            TGCard {
                TGSectionHeader(title: "что войдёт")
                ForEach(contents, id: \.0) { title, count in
                    HStack {
                        Text(title).textStyle(AppFont.body)
                        Spacer()
                        Text("\(count)").textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                    }
                    .frame(minHeight: 34)
                }
                TGExplainer(text: "Ничего не надо вспоминать: всё, что попадёт в отчёт, уже записано в бытовой ленте.")
            }

            ShareLink(
                item: CSVFile(name: "togo-otchet.csv", text: Exporter.csv(events: events)),
                preview: SharePreview("Отчёт Togo · CSV")
            ) {
                TGCard {
                    TGListRow(title: "Выгрузить CSV", value: "без подписки", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Отчёт")
        .cinemaScreen(экран: .sub("report"))
    }

    private var contents: [(String, Int)] {
        [
            ("Приёмы и пропуски", events.filter { $0.kind == .dose }.count),
            ("Стул и симптомы", events.filter { $0.kind == .stool || $0.kind == .incident }.count),
            ("Вес и аппетит", events.filter { $0.kind == .weight || $0.kind == .meal }.count),
            ("Занятия", events.filter { $0.kind == .training }.count),
        ]
    }
}

/// Вес. Приложение не считает норму само и не ставит целей по проценту:
/// коридор называет врач.
///
/// # Право: `editProfile`, и оно НАЗВАНО ИСТОЧНИКОМ, а не выбрано мной
///
/// **Замер 26.10.2026: прав здесь не было вовсе.** Ни `canEdit`,
/// ни `appState.can(` — при трёх входах (`HealthScreen:527`,
/// `ProfileScreen:116`, `DogTab:411`). Поле ввода, кнопка «Записать»,
/// создание и удаление взвешивания были открыты **наблюдателю
/// и помощнику**, то есть гостю и маме без прав.
///
/// Цена не косметическая, и она записана тут же, у вердикта:
/// **«вес это та величина, от которой считается доза»**. Удалённое
/// взвешивание откатывает `dog.weightKg` к предыдущему замеру
/// (`delete`), а от него считают дозу и коридор.
///
/// **Какое право — ответил сам `Permission`, и это дешевле спора:**
///
/// ```
/// Permission.editProfile.detail   «порция, ВЕС, напоминания, занятия»
///                                 ← вес назван поимённо
/// Permission.editTreatment.detail «препараты, часы, окно натощак»
///                                 ← веса нет
/// ProfileScreen:26                уже гасит .editProfile, а это
///                                 ОДИН ИЗ ТРЁХ входов сюда
/// ```
///
/// То есть у двух входов из трёх ответ уже дан, и дан одинаково.
///
/// **Почему НЕ `editTreatment`, хотя рядом `Prescription.dogWeightKg`
/// стоит под ним.** Это две разные величины одного имени:
/// `dogWeightKg` — вес, ОТ КОТОРОГО считали дозу в тот день, поле
/// медицинского бланка, вводимое задним числом (и нарочно
/// не подставляемое, `PrescriptionEditor:276`). Здесь — текущий вес,
/// бытовой замер, который делает тот, кто держит собаку на весах.
/// `editTreatment` по умолчанию есть **только у владельца**
/// (`defaultPermissions`), и под ним мама-со-владелец не смогла бы
/// записать взвешивание вовсе.
///
/// > **Право выбиралось не по тому, насколько величина важна,
/// > а по тому, кто её производит.** Читают вес все — и чтение
/// > ниже не закрыто ни на строку.
///
/// # Орган, которого роль не даёт, УБРАН, а не выключен
///
/// Ответ дизайна круга 5, п. 2: «органы, которых роль не даёт, гостю
/// не показываются; выключенными их не делаем. Там, где орган можно
/// убрать совсем, правильнее убрать». Карточка «взвесить сейчас» —
/// **чистый ввод**, смотреть в ней нечего, поэтому без права её нет
/// вовсе; отказ при этом назван словом один раз, `ПлашкаПрава`
/// сверху. Карточка текущего веса, цель врача и история остаются:
/// их читают все.
struct WeightScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var newWeight = ""

    /// Фокус поля веса — единственного `.decimalPad` на экране.
    @FocusState private var весВФокусе: Bool

    /// Вес правит тот, кто правит профиль и уход: это бытовой замер,
    /// а не запись из бланка. Разбор — в голове экрана.
    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            CinemaHeader("Вес", надпись: "коридор врача", отступы: false)
            // Плашка — ДО первого отказа, а не после нажатия: ниже
            // пропадают карточка ввода и дорога к удалению, и без
            // слова это читалось бы как «экран недоделан».
            if !canEdit { ПлашкаПрава(право: .editProfile) }
            TGCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(dog.map { Fmt.weight($0.weightKg) } ?? "—").textStyle(AppFont.display)
                    Spacer()
                    // **Три состояния, а не два.** Прежняя редакция
                    // спрашивала `!dog.isWeightInRange` и всё остальное
                    // сваливала в `else` — а предикат отвечает `true`
                    // на ДВА разных состояния: «вес внутри коридора»
                    // и «коридора не существует» (`Dog.swift:497`,
                    // `guard … else { return true }`). У собаки без
                    // назначенного врачом коридора под её весом стояло
                    // зелёное «в норме».
                    //
                    // > **`else` ловил два состояния и говорил о них
                    // > одно.** Утверждение, которого приложение
                    // > сделать не может — и вес это та величина,
                    // > от которой считается доза.
                    //
                    // Предикат не тронут: для ворот он прав. Спрашиваем
                    // `weightVerdict`, и он построен на `LabNorm`, где
                    // правило «нормы нет → так и скажи» уже живёт.
                    //
                    // **Коридора нет — МОЛЧИМ, а не придумываем слово.**
                    // Новый ключ под заморозкой текстов дал бы русскую
                    // строку французу ровно на медицинском экране;
                    // а молчание согласовано с соседней строкой —
                    // «цель … поставил врач» ниже показывается по тем же
                    // двум полям, то есть вердикт и цель появляются
                    // и исчезают вместе. Если решат словом — адрес здесь.
                    if let dog {
                        switch dog.weightVerdict {
                        case .withinRange:
                            Text("в норме").textStyle(AppFont.caption.color(Token.Action.doneText))
                        case .below, .above:
                            Text("вне коридора").textStyle(AppFont.caption.color(Token.Status.waitingText))
                        case .normUnknown, .indeterminate:
                            EmptyView()
                        }
                    }
                }
                if let low = dog?.targetWeightLow, let high = dog?.targetWeightHigh {
                    Text("цель \(Fmt.weight(low)) — \(Fmt.weight(high)) · поставил врач").textStyle(AppFont.caption)
                }
            }

            карточкаВзвешивания

            TGCard {
                TGSectionHeader(title: "история")
                let history = (dog?.weights ?? []).sorted { $0.date > $1.date }.prefix(12)
                if history.isEmpty {
                    TGExplainer(text: "Пока одно значение — то, что ты ввела при добавлении собаки.")
                } else {
                    ForEach(Array(history)) { entry in
                        // История читается всеми, а удаляется по праву:
                        // без права строка остаётся строкой, а не
                        // выключенной кнопкой, ведущей в тишину.
                        Button { if canEdit { removing = entry } } label: {
                            HStack {
                                Text(Fmt.shortDay(entry.date)).textStyle(AppFont.caption)
                                Spacer()
                                Text(Fmt.weight(entry.kg)).textStyle(AppFont.numeric(15))
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                    // Взвешивание — единственное, что нельзя было исправить.
                    // Опечатка «12,4 → 124» оставалась в графике навсегда
                    // и уводила коридор веса вместе с собой.
                    //
                    // Подсказка про удаление — только тому, кто может
                    // удалить: иначе она посылает человека делать то,
                    // чего ему не дадут.
                    if canEdit {
                        TGExplainer(text: "Ошиблась — тапни по строке и удали.")
                    }
                }
            }
        }
        .navigationTitle("Вес")
        .cinemaScreen(экран: .sub("weight"))
        // Выход с цифровой клавиатуры: у `.decimalPad` своей клавиши
        // возврата нет.
        .готовоНадКлавиатурой { весВФокусе = false }
        .confirmationDialog("Удалить взвешивание?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible,
                            presenting: removing) { entry in
            Button("Удалить", role: .destructive) { delete(entry) }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: { entry in
            Text("\(Fmt.shortDay(entry.date)) · \(Fmt.weight(entry.kg)). Из графика и из коридора веса запись тоже уйдёт.")
        }
    }

    /// Карточка «взвесить сейчас» — **чистый ввод, и без права её нет
    /// вовсе**, а не выключенной (ответ дизайна круга 5, п. 2).
    /// Смотреть в ней нечего: текущий вес, цель врача и история стоят
    /// отдельными карточками и открыты всем.
    @ViewBuilder
    private var карточкаВзвешивания: some View {
        if canEdit {
            TGCard {
                TGSectionHeader(title: "взвесить сейчас")
                HStack(spacing: Token.Space.s12) {
                    TextField("4,1", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .focused($весВФокусе)
                        .textStyle(AppFont.numeric(24))
                    Text("кг").textStyle(AppFont.caption)
                    TGButton(title: "Записать", size: .medium, fullWidth: false,
                             isEnabled: parsedWeight != nil) { save() }
                }
                // Правило круга 5, п. 1. Условие и действие здесь
                // смотрят на ОДНУ величину (`parsedWeight` читают оба),
                // — проверено, и это не тот класс, что в запасе корма.
                // Не хватало только слова.
                //
                // Строка говорит про ФОРМАТ, а не про пустоту:
                // выключенной кнопка остаётся и при набранном
                // «4,1 кг» или «4.1.2» — то есть при непустом поле,
                // и вот тогда тишина и непонятна.
                if parsedWeight == nil, !newWeight.isEmpty {
                    Text("Нужно одно число — например 4,1")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
            }
        }
    }

    /// Удалить взвешивание, вернув текущий вес к предыдущему замеру.
    ///
    /// **Право спрашивается и ЗДЕСЬ, а не только у органа.** Орган
    /// убран показом, и этого мало: `removing` — состояние, которое
    /// живёт дольше одного кадра, а право меняется извне (владелец
    /// снимает его в «Семье», и обмен приносит это на чужой телефон).
    /// Проверка у показа отвечает на «рисовать ли кнопку»,
    /// а у записи — на «можно ли писать», и это разные вопросы.
    private func delete(_ entry: WeightEntry) {
        guard canEdit, let dog else { return }
        // Надгробие вместо `context.delete`: вес — то, от чего считается
        // доза, и расхождение веса между двумя людьми даёт расхождение
        // дозы. Удаление, не доехавшее до второго человека, оставляло
        // ему точку, которой у хозяйки уже нет.
        let откатНадгробия = ОбщееУдаление.удалить(entry)
        // Текущий вес показывается по всему приложению — если удалили
        // последнее взвешивание, он обязан откатиться, а не остаться
        // от только что стёртой записи.
        let былВес = dog.weightKg
        // `dog.weights` уже отсеивает надгробия, то есть эта запись
        // из него выпала строкой выше; фильтр по `persistentModelID`
        // оставлен как есть — он больше не нужен, но и не врёт,
        // а убрать его значило бы связать откат с порядком двух правок.
        let rest = dog.weights.filter { $0.persistentModelID != entry.persistentModelID }
        if let latest = rest.max(by: { $0.date < $1.date }) {
            dog.weightKg = latest.kg
        }
        guard context.persist(otherwise: {
            dog.weightKg = былВес
            откатНадгробия()
        }) else {
            Haptics.warning()
            return appState.showFailure("Взвешивание не удалилось · попробуй ещё раз")
        }
        Haptics.warning()
        removing = nil
    }

    /// Какую запись предлагается удалить.
    @State private var removing: WeightEntry?

    private var parsedWeight: Double? {
        Double(newWeight.replacingOccurrences(of: ",", with: "."))
    }

    /// Записать взвешивание. Право — как у удаления, и по той же
    /// причине: `newWeight` набран раньше, чем право могло исчезнуть.
    private func save() {
        guard canEdit, let dog, let kg = parsedWeight else { return }
        let entry = WeightEntry(kg: kg)
        entry.dog = dog
        context.insert(entry)
        dog.weightKg = kg

        // Взвесили — значит, напоминание «Взвесить» отработало. Просить
        // человека отметить то же самое второй раз незачем.
        let задача = dog.careTasks.first { $0.title == "Взвесить" }
        let былоСделано = задача?.lastDone
        задача?.markDone()

        guard context.persist(otherwise: {
            context.delete(entry)
            задача?.lastDone = былоСделано
        }) else {
            Haptics.warning()
            return appState.showFailure("Вес не записался · попробуй ещё раз")
        }
        newWeight = ""
        Haptics.success()
    }
}
