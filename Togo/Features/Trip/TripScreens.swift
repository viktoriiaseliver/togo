import SwiftUI
import SwiftData

/// Режим путешествия. Устроен как «Фокус»: включается на даты, меняет главный
/// экран и сам выключается. Не место, куда надо ходить.
struct TripSetupScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var trips: [Trip]

    @State private var destination = ""
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now
    @State private var transport: TransportKind = .car
    @State private var hours = 5.0
    @State private var lodging = ""

    /// Кличка в шапке, а не вторым заголовком над ней.
    ///
    /// **Этот экран был единственным из сорока, который давал каркасу
    /// `title:` И клал внутрь `CinemaHeader`** (замер 28.10.2026:
    /// 41 вызов `CinemaHeader` в `Togo/Features`, у сорока каркас
    /// зовётся `TGScreen {`, здесь — `TGScreen(title:)`). Выходило
    /// три строки заголовка подряд:
    ///
    /// ```
    /// Едем с Стичем      ← title каркаса, AppFont.screenTitle
    /// СБОРЫ И ДОРОГА     ← надпись CinemaHeader, капсом
    /// Поездка            ← заголовок CinemaHeader, 36 pt
    /// ```
    ///
    /// Надпись-кикер принадлежит нижнему заголовку, а стояла между
    /// двумя — отсюда «поплыли отступы» в отзыве 27.10.2026. Плюс
    /// плавающая кнопка «назад» (`.cinemaScreen()`) рассчитана на то,
    /// что первой строкой идёт `CinemaHeader`, и ложилась на чужой
    /// заголовок.
    ///
    /// Кличка не потеряна — она стала самим заголовком, как у карточки
    /// участника семьи (`FamilyScreen:1108`, `CinemaHeader(значение:)`).
    /// `значение:`, а не `ключ:`, потому что внутри кличка: литерал
    /// ушёл бы в каталог целиком вместе с ней.
    private var шапка: String {
        String(localized: "Едем с \(dog.flatMap(\.nameIfAny) ?? String(localized: "собакой"))")
    }

    var body: some View {
        TGScreen {
            CinemaHeader(значение: шапка, надпись: "сборы и дорога", отступы: false)
            TGExplainer(text: "Режим включится сам в день отъезда и выключится, когда вернётесь.")

            TGCard(spacing: 0) {
                LabeledField(label: "Куда") {
                    // Был настоящий маршрут владелицы, и он переводился:
                    // `en/fr Nice → Lyon`, `uk Ніцца → Ліон`. Стрелка —
                    // единственное, что пример сообщал о форме поля;
                    // «откуда и куда» сообщает её словами.
                    //
                    // Прежнее решение в `PlaceholderOriginTests` звало
                    // это `.пример` («города только пример»). Оно снято
                    // мной 25.10.2026 и было без хозяина и без даты —
                    // в отличие от соседнего решения Виктории
                    // про `Lévothyrox` (15.10.2026, `4e836a2`),
                    // которое не тронуто.
                    TextField("откуда и куда", text: $destination)
                }
                TGDivider()
                DatePicker("Когда", selection: $start, displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                    // `in: start...` у «По» не двигает уже выбранный конец:
                    // перенеси начало за него — и поездка сохранялась
                    // с концом раньше начала.
                    .onChange(of: start) { _, новое in
                        if end < новое { end = новое }
                    }
                TGDivider()
                DatePicker("По", selection: $end, in: start..., displayedComponents: .date)
                    .frame(minHeight: Token.Size.tapTarget)
                TGDivider()
                LabeledField(label: "Где живём") {
                    TextField("отель, с собакой можно", text: $lodging)
                }
            }

            TGCard {
                TGSectionHeader(title: "как", subtitle: "транспорт определяет окна натощак и остановки")
                TGChipGroup(
                    items: TransportKind.allCases,
                    title: \.title,
                    isSelected: { $0 == transport }
                ) { transport = $0 }
                if transport == .car {
                    Stepper(value: $hours, in: 1...20, step: 0.5) {
                        HStack {
                            Text("В дороге").textStyle(AppFont.body)
                            Spacer()
                            // Было `"\(hours, specifier: "%.1f") ч"` —
                            // «5.0 ч»: точка вместо запятой и нулевой знак.
                            // Единицу и разделитель называет система,
                            // половина часа выходит «5 ч 30 мин».
                            Text(.готовая(Fmt.hoursMinutes(hours * 3600)))
                                .textStyle(AppFont.numeric(15))
                        }
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
                TGExplainer(text: .готовая(transport.windowsExplainer))
            }

            if let dog { PackingListCard(dog: dog, days: dayCount) }
        } bottom: {
            // Правило дизайна круга 5, п. 1: выключенная кнопка
            // допустима, только если рядом словом сказано, чего
            // не хватает. Форма — по образцу запаса корма (`d569d01`):
            // строка над кнопкой, на ТОЙ ЖЕ величине, что ворота.
            //
            // Триммить условие тут нельзя молча: `save()` берёт
            // `destination` как есть, и свести величины надо было бы
            // в обе стороны сразу. Названо открытым пунктом, а строка
            // ставится на ту величину, что в воротах СЕЙЧАС.
            VStack(spacing: Token.Space.s8) {
                if destination.isEmpty {
                    Text("Напиши, откуда и куда — по этому собираются вещи")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: "Включить режим", systemImage: "car", isEnabled: !destination.isEmpty) { save() }
            }
        }
        .navigationTitle("Поездка")
        .cinemaScreen(экран: .sub("trip"))
        .usageScreen(.trip)
    }

    private var dayCount: Int {
        max(1, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func save() {
        guard let dog else { return }
        // **Якорь в полдень, а не «как отдал пикер».** `DatePicker`
        // с `displayedComponents: .date` сохраняет ВРЕМЯ СУТОК у
        // привязанного значения, и в базу уезжает момент, нередко
        // близкий к полуночи. У семьи западнее владельца такой момент
        // попадает в предыдущие сутки, и первый день поездки читается
        // как второй. Замер по поясам — в `CalendarDay`.
        let trip = Trip(destination: destination,
                        startDate: CalendarDay.anchored(start),
                        endDate: CalendarDay.anchored(end),
                        transport: transport)
        trip.travelHours = hours
        trip.lodging = lodging
        trip.dog = dog
        context.insert(trip)
        // Здесь была одна вставка без сохранения и сразу «успех»:
        // не сохранилось — экран закрывался, будто поездка есть.
        guard context.persist(otherwise: { context.delete(trip) }) else {
            Haptics.warning()
            appState.showFailure(String(localized: "Поездка не сохранилась · нажми ещё раз"))
            return
        }
        Haptics.success()
        dismiss()
    }
}

nonisolated extension TransportKind {
    var windowsExplainer: String {
        switch self {
        case .car: String(localized: "Остановки каждые 2 часа: вода и пять минут походить. Приложение напомнит и запишет остановку одним тапом.")
        case .plane: String(localized: "Последняя еда за 4 часа, вода за час, долгий выход за 40 минут. В самолёте на пустой желудок спокойнее.")
        case .train: String(localized: "Выход на длинных стоянках, вода чаще обычного: в вагоне суше.")
        }
    }

    /// Оговорка под окнами: «это общая практика, а не назначение».
    ///
    /// **Обязана называть тот транспорт, который на экране.** До 28.09
    /// под окнами автомобильной поездки стоял литерал про перелёт:
    /// значок машины, строка «Выход перед машиной» — и объяснение
    /// «перед перелётом» между ними. Так это и приехало отзывом
    /// «Странный экран и странный текст» 25.09.
    ///
    /// Три целых предложения, а не подстановка существительного
    /// в общий шаблон: падеж и предлог в других языках так не собираются.
    var windowsDisclaimer: String {
        switch self {
        case .car:
            String(localized: "Окна натощак перед поездкой — общая практика, а не назначение. Если собака на терапии, приложение сведёт их с приёмами и покажет, где конфликт.")
        case .plane:
            String(localized: "Окна натощак перед перелётом — общая практика, а не назначение. Если собака на терапии, приложение сведёт их с приёмами и покажет, где конфликт.")
        case .train:
            String(localized: "Окна натощак перед поездом — общая практика, а не назначение. Если собака на терапии, приложение сведёт их с приёмами и покажет, где конфликт.")
        }
    }

    /// Окна перед дорогой считаются от времени выезда.
    func windows(before departure: Date) -> [(String, Date, String)] {
        switch self {
        case .plane:
            [("−4 ч", departure.addingTimeInterval(-4 * 3600), "Последняя еда"),
             ("−1 ч", departure.addingTimeInterval(-3600), "Убрать воду"),
             ("−40 м", departure.addingTimeInterval(-40 * 60), "Долгий выход")]
        case .car:
            [("−2 ч", departure.addingTimeInterval(-2 * 3600), "Последняя еда"),
             ("−20 м", departure.addingTimeInterval(-20 * 60), "Выход перед машиной")]
        case .train:
            [("−2 ч", departure.addingTimeInterval(-2 * 3600), "Последняя еда"),
             ("−30 м", departure.addingTimeInterval(-30 * 60), "Выход перед посадкой")]
        }
    }
}

/// Сборы считаются из веса и порции — а не из общих таблиц.
struct PackingListCard: View {
    let dog: Dog
    let days: Int

    var body: some View {
        TGCard {
            TGSectionHeader(title: "что взять на \(Fmt.days(days))",
                            subtitle: dog.servingGrams > 0
                                ? "посчитано из веса \(Fmt.weight(dog.weightKg)) и порции \(dog.servingGrams) г"
                                : "норма не записана — корм посчитать нечем")
            ForEach(items, id: \.0) { title, amount, note in
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    HStack {
                        Text(title).textStyle(AppFont.bodyEmphasis)
                        Spacer()
                        Text(amount).textStyle(AppFont.numeric(17))
                    }
                    Text(note).textStyle(AppFont.caption)
                }
                .frame(minHeight: 48)
            }
            TGExplainer(text: "Корм отсыпать в зип-пакеты по дням и подписать. Один пакет — в ручную кладь: если чемодан уедет не туда, у собаки останется ужин.")
            TGDivider()
            Text("Числа посчитаны по нему, а не по общим таблицам. Дозировки и всё медицинское сверь с врачом — приложение только считает и напоминает.")
                .textStyle(AppFont.caption)
        }
    }

    /// Запас — два кормления сверх поездки, вода в жару в полтора раза больше.
    ///
    /// **Без нормы строка корма — прочерк, а не ноль.** Арифметика
    /// `норма × дни` при ненаписанной норме даёт ноль, и «Корм 0 г»
    /// в списке сборов человек читает как «корма не надо». Это худший
    /// из возможных нулей: его видно в аэропорту, а не на экране,
    /// где можно переспросить.
    ///
    /// # Граммы переведены в килограммы — отзыв 27.10.2026
    ///
    /// Дословно: «Переведи граммы как-то в понятные цифры». На кадре
    /// 23:01 — `Корм 13160 г` на поездку в 62 дня. Число верное
    /// и нечитаемое: на вопрос «влезет ли это в чемодан» отвечает
    /// `13,2 кг`, а не пять цифр подряд.
    ///
    /// **Точность не потеряна, а переехала в подпись.** Крупно —
    /// килограммы, подписью — ровное число граммов: корм отсыпают
    /// в зип-пакеты по дням, и там считают граммами. Перевод делает
    /// `Fmt.foodMass`, то есть одно место на весь проект.
    ///
    /// # И эти строки ВООБЩЕ не переводились
    ///
    /// Замер 28.10.2026, попутно к тому же кадру. Кортеж объявлен
    /// `[(String, String, String)]`, а `Text(строка)` со **значением**
    /// типа `String` рисует дословно, мимо каталога — это известный
    /// класс, записанный в правилах локализации. То есть «Корм»,
    /// «Вода в дорогу», «Пакеты» и все три подписи показывались
    /// по-русски на пяти языках, при том что ключи в каталоге
    /// переведены и лежат готовыми.
    ///
    /// Числа идут в строку через `.formatted()` намеренно: тогда
    /// компилятор строит ключ с `%@`, а не с `%lld`, и ключ совпадает
    /// с тем, что в каталоге уже переведено. Заодно появляется
    /// разделитель тысяч — «13 160» вместо «13160».
    private var items: [(String, String, String)] {
        let food = dog.dailyGrams * days + dog.servingGrams * 2
        let наДни = dog.dailyGrams * days
        let water = Double(dog.waterNormMl * days) * 1.5 / 1000
        return [
            (String(localized: "Корм"),
             dog.dailyGrams > 0 ? Fmt.foodMass(food) : "—",
             dog.dailyGrams > 0
                 ? String(localized: "ровно \(food.formatted()) г")
                     + " · "
                     + String(localized: "\(наДни.formatted()) г на дни плюс запас на два кормления")
                 // Имя экрана НЕ цитируется: цитата обязана дословно
                 // совпасть с переводом своего ключа в каталоге, и
                 // сторож цитат ловил это трижды за сутки. Дорога
                 // названа словами, а не подписью кнопки.
                 : String(localized: "сначала запиши дневную норму в режиме питания — из неё считается всё")),
            (String(localized: "Вода в дорогу"),
             Fmt.litres(water),
             String(localized: "его норма ≈ \(dog.waterNormMl.formatted()) мл в день, в жару больше · складная поилка")),
            (String(localized: "Пакеты"),
             String(localized: "\((days * 4).formatted()) шт"),
             String(localized: "по четыре на день, с запасом")),
        ]
    }
}

/// Блок дороги на главном. В поездке он встаёт между окном натощак и таймлайном.
struct TripTodayBlock: View {
    let trip: Trip
    let dog: Dog?
    let now: Date

    var body: some View {
        TGCard {
            HStack {
                Image(systemName: trip.transport.symbol)
                    .font(.system(size: Token.Size.iconMd, weight: .medium))
                    .foregroundStyle(Token.Status.doneText)
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(trip.destination).textStyle(AppFont.cardTitle)
                    Text("день \(trip.dayNumber(on: now)) из \(trip.dayCount())").textStyle(AppFont.caption)
                }
                Spacer(minLength: 0)
            }
            TGDivider()
            // Список «до выезда» живёт до выезда, а не весь первый день.
            //
            // Стояло `dayNumber(on: now) <= 1`: условие считало ДНИ,
            // а содержимое считает ВРЕМЯ ВЫЕЗДА. На кадре отзыва 25.09
            // в 15:56 экран звал «−2 ч последняя еда 07:00» и «−20 м
            // выход перед машиной 08:40» — семь часов после выезда,
            // предлагая сделать то, чего уже не сделать.
            if now < departure {
                departureWindows
            } else {
                onSiteAdvice
            }
        }
    }

    /// Момент выезда: минута выезда на дне отъезда.
    ///
    /// Через `Calendar.date(minuteOfDay:on:)` (`DayTime.swift:20`), а не
    /// сложением секунд с началом дня: в сутках перевода часов не 24 часа,
    /// и выезд в 09:00 оказывался в 08:00 или в 10:00. Промах здесь стоит
    /// дороже часа — от этого момента отсчитываются ВСЕ окна «до выезда»
    /// («−2 ч последняя еда», «−20 м выход перед машиной»), и им же
    /// решается, показывать список сборов или советы на месте.
    private var departure: Date {
        Calendar.current.date(minuteOfDay: trip.departureMinuteOfDay, on: trip.startDate)
    }

    private var departureWindows: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: "до выезда")
            ForEach(trip.transport.windows(before: departure), id: \.0) { offset, at, title in
                HStack(spacing: Token.Space.s12) {
                    Text(offset)
                        .textStyle(AppFont.numeric(13, weight: .medium))
                        .fixedSize()
                        .frame(minWidth: 44, alignment: .leading)
                    Text(title).textStyle(AppFont.body)
                    Spacer(minLength: 0)
                    Text(Fmt.clock(at)).textStyle(AppFont.caption)
                }
                .frame(minHeight: 38)
            }
            TGExplainer(text: .готовая(trip.transport.windowsDisclaimer))
        }
    }

    private var onSiteAdvice: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            TGSectionHeader(title: "в незнакомом городе")
            Text("Три места, а не карта с сотней точек: нужен один ответ на вопрос «куда сейчас».")
                .textStyle(AppFont.caption)
            if let dog {
                Text("Норма воды ≈ \(dog.waterNormMl) мл в день. В жару смотри на эту строку первым делом: смена воды и корма чаще всего даёт сбой именно тут.")
                    .textStyle(AppFont.caption)
            }
        }
    }
}
