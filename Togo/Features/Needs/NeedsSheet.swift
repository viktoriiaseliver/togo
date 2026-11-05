import SwiftUI
import SwiftData

/// «Просится» — главная кнопка приложения и единственное место, где приложение
/// может незаметно испортить поведение. **Пять случаев вердикта и шесть
/// разных объяснений** (у `.unknown` три причины), и «Вывожу» первой
/// кнопкой во всех: вердикт не блокирует выход.
///
/// **Здесь было написано «четыре исхода» — 07.10.2026 это посчитано
/// и оказалось неверно**, ровно как и та же фраза в `NeedVerdict.swift:3`.
/// Числа в документации стареют молча: `.episode` и `.silence`
/// приехали позже, а строка осталась и читается ВМЕСТО кода —
/// тем же способом, каким у Gamut имя теста пять дней рассказывало
/// отменённое поведение.
///
/// # Редизайн iOS 28, кадр 07 «Просится · вердикт»
///
/// Собрано по кадру `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/07.png`,
/// решение Виктории 22.10.2026. Сверху вниз, как на кадре: шапка
/// «Просится · по времени и прошлым дням» → карточка вердикта (фото
/// собаки в круге, подпись исхода прописными, крупный заголовок,
/// объяснение) → карточка фактов тремя парами «ключ — значение» →
/// «как попросил» чипами прямо здесь → строка дозы с кнопкой «Дал» →
/// «Вывожу» и второе действие внизу.
///
/// **Что изменилось против прежней вёрстки, и почему это не косметика:**
///
/// ```
/// было                              стало (кадр 07)
/// заголовок шторки = исход          заголовок = «Просится», исход
///   вердикта, подзаголовок = badge    внутри карточки рядом с фото
/// факты одной слитной строкой       три пары «ключ — значение» ровно
///   (`factLine`)                      из того, ЧЕМ СЧИТАЛСЯ вердикт
/// «как попросил» — отдельной        чипы в этой же шторке, до выхода
///   шторкой ПОСЛЕ выхода
/// доза рядом — только текстом       текст и кнопка «Дал»
/// ```
///
/// **Расхождения с кадром названы, а не обойдены** (их правит тот, у кого
/// есть на это право):
///
/// - На кадре подпись над заголовком — **фиксированное «Похоже, что»**.
///   Здесь стоит `verdict.badge`, то есть сам исход («срочно», «похоже
///   на нужду», «неясно», «отметок мочи нет», «эпизод»). Причина:
///   пять исходов, названных прямо, — решение продукта, а «Похоже,
///   что» + «Выведи сейчас» не складывается во фразу ни на одном
///   из пяти. Фиксированную подпись вернуть — одна строка, и тогда
///   исход перестаёт называться словом.
/// - На кадре у заголовка **26 pt**; такой ступени в токенах нет вовсе
///   (`primitive.font.size`: 20 → 34). Выдумывать число нельзя — оно
///   уедет дизайнеру тем же именем и разойдётся с макетом молча.
///   Взята ближайшая существующая, 20; недостающая ступень названа
///   в отчёте.
/// - На кадре пятый чип — **«Другое…»** со свободным вводом. У нас
///   `LogEvent.askSignal` это перечисление из пяти случаев, свободного
///   текста ему некуда положить. Нарисовать чип значило бы завести
///   **вход без механизма**: человек впишет своими словами и потеряет
///   написанное.
/// - Чипы на кадре — пилюли (радиус 999), у нас `TGChip` стоит
///   на `Radius.tile` = 16. Это компонент дизайн-системы, не экрана.
struct NeedsSheet: View {
    let dog: Dog?

    /// Готовый срез фактов вместо чтения из базы — вход для галереи.
    ///
    /// Без него шесть состояний вердикта требуют шести собак с нужной
    /// историей событий в SwiftData, то есть поверхность остаётся
    /// **проверяемой только живой собакой**. Тот же ход, что
    /// у `WalkActivityView`: не новый вид рядом с настоящим,
    /// а второй вход в настоящий — иначе кадр доказывал бы, что верна
    /// копия.
    var демоСигналы: NeedSignals?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(Settings.self) private var settings
    @State private var askSignal = false

    /// Считаем один раз при открытии: тело шторки обращается к вердикту
    /// и к фактам по три раза, а каждый расчёт проходит всю историю.
    @State private var signals = NeedSignals()
    @State private var verdict: NeedVerdict = .unknown(reason: .ambiguous)

    /// Спрашивать ли «как попросил» в этой шторке.
    ///
    /// Считается **при открытии**, а не в момент записи выхода: чипы
    /// стоят выше кнопки «Вывожу», то есть вопрос задаётся до того, как
    /// выход появится в дневнике. Правило то же и живёт в одном месте —
    /// `Diary.shouldAskHowAsked`: при смене сигнала или раз в пять
    /// выходов.
    @State private var спрашиватьКакПопросил = false

    /// Что человек ответил чипами. Пока выхода нет, положить ответ
    /// некуда — он уезжает в событие в `startOuting()`.
    @State private var какПопросил: AskSignal?

    /// Доза уже отмечена из этой шторки. Кнопка «Дал» одноразовая:
    /// `DoseScheduler.markGiven` вторую отметку не ставит, но кнопка,
    /// которая после нажатия выглядит нажимаемой, — приглашение
    /// к двойной дозе.
    @State private var дозаОтмечена = false

    private func evaluate() {
        // Галерея подставляет срез фактов; вердикт всё равно считает
        // НАСТОЯЩИЙ движок. Подставь сюда готовый вердикт — и кадр
        // доказывал бы, что верна подпись под картинкой, а не что
        // правило считает то, что написано.
        signals = демоСигналы
            ?? Diary.signals(dog?.events ?? [], episodeActive: appState.isEpisodeActive)
        verdict = VerdictEngine.evaluate(signals)
        // В галерее собаки нет, и спрашивать не у кого: ответ класть
        // было бы некуда, а чипы на кадре читались бы как рабочие.
        спрашиватьКакПопросил = dog.map { Diary.shouldAskHowAsked($0.events) } ?? false
    }

    /// «Через 20 мин доза · Ветмедин» или «Доза была 20 мин назад · …».
    ///
    /// Знак решает фразу, а не модуль: «через» и «назад» — разные
    /// слова, и выбрать между ними по `abs()` нельзя. Знак для этого
    /// и лежит в `Рядом.через`.
    ///
    /// Формат **точный** (`Fmt.duration`), а не промежуток ленты
    /// (`Fmt.gap`): тот округляет до получаса нарочно, и «через
    /// 20 минут» превратилось бы в «через 30». Пара этих функций уже
    /// стоила нам подписи, врущей на восемь минут, — рядом с точным
    /// временем округление становится потерей данных.
    private func дозаРядомТекст(_ доза: WalkDose.Рядом) -> String {
        let сколько = Fmt.duration(abs(доза.через))
        return доза.через >= 0
            ? String(localized: "Через \(сколько) доза · \(доза.препарат)")
            : String(localized: "Доза была \(сколько) назад · \(доза.препарат)")
    }

    var body: some View {
        TGSheet(title: "Просится",
                subtitle: "по времени и прошлым дням",
                closeTitle: "Отмена") {
            вердиктКарточка
            фактыКарточка

            if case .unknown(.notEnoughData) = verdict {
                TGExplainer(text: "Через три-четыре дня приложение выучит его интервалы и начнёт подсказывать, настоящая ли нужда. Пока — выводи, как обычно.")
            }

            какПопросилБлок
            дозаБлок
        } footer: {
            // Главное действие закреплено внизу: до него дотягивается большой
            // палец, и оно не уезжает вместе с текстом вердикта.
            TGButton(title: "Вывожу", systemImage: "figure.walk.departure") { startOuting() }
            TGButton(title: .готовая(verdict.alternativeAction), variant: .secondary, size: .medium) { dismiss() }
        }
        .presentationDetents([.fraction(Self.высотаПоКадру), .large])
        // Демо-показ в журнал не пишем: шесть состояний галереи дали бы
        // шесть посещений «Просится», которых человек не делал.
        .usageScreen(демоСигналы == nil ? .needs : nil)
        .task { evaluate() }
        .sheet(isPresented: $askSignal) {
            HowAskedSheet(dog: dog) { dismiss() }
        }
    }

    // MARK: Вердикт

    /// Фото собаки, подпись исхода, крупный заголовок и объяснение.
    ///
    /// Аватар берёт `Dog.initial` и `Dog.photo`: кличка показывается
    /// через одну точку, напрямую `name` читать нельзя.
    private var вердиктКарточка: some View {
        TGCard {
            HStack(alignment: .top, spacing: Token.Space.s16) {
                TGAvatar(initial: dog?.initial ?? "·",
                         image: dog?.photo,
                         size: Self.аватар)
                VStack(alignment: .leading, spacing: Token.Space.s6) {
                    Text(verbatim: verdict.badge)
                        .textStyle(AppFont.caps)
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .wraps()
                    Text(verbatim: verdict.title)
                        .textStyle(Self.стильЗаголовка.color(цветИсхода))
                        .wraps()
                    Text(verbatim: VerdictEngine.explanation(verdict, signals))
                        .textStyle(AppFont.caption)
                        .wraps()
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Фото собаки в круге. 72 pt на кадре; ступени `avatarMd` = 40
    /// и `avatarSm` = 26 обе меньше втрое, поэтому число стоит здесь,
    /// а недостающая ступень названа в отчёте.
    private static let аватар: CGFloat = 72

    /// Какую долю экрана занимает шторка на первом показе.
    ///
    /// **Было `.medium`, то есть ровно половина — и этого мало.**
    /// На кадре 07 (424×896) ручка шторки стоит на 245-й точке сверху:
    /// `(896 − 245) / 896 ≈ 0,73`. При `.medium` человек на первом
    /// показе видит карточку вердикта и больше ничего — ни фактов,
    /// ни чипов, ни кнопки «Вывожу», которая и есть главное действие.
    ///
    /// Число снято С КАДРА и названо дробью, а не точками: доля
    /// переживает смену устройства, 651 pt — нет.
    private static let высотаПоКадру: CGFloat = 0.73

    /// Заголовок исхода. На кадре 26 pt, такой ступени в токенах нет —
    /// берём ближайшую существующую (`section` = 20) и не выдумываем
    /// своего числа.
    private static var стильЗаголовка: TextStyleToken {
        TextStyleToken(size: Token.FontSize.section,
                       weight: Token.FontWeight.bold,
                       color: Token.Ink.primary,
                       relativeTo: .title3)
    }

    /// Цвет заголовка исхода — то, чем кадр отличает срочное от ровного.
    ///
    /// Прототип: красный у «Выведи сейчас», синий у «Выведи» и у эпизода,
    /// обычный у остальных. Терракот и ссылка — наши имена для этих
    /// двух ролей, своих значений экран не заводит.
    private var цветИсхода: Color {
        switch verdict {
        case .urgent: Token.Status.overdueText
        case .likelyNeed, .episode: Token.Ink.link
        case .unknown, .probablyAttention: Token.Ink.primary
        }
    }

    // MARK: Факты

    /// Три пары «ключ — значение» и строка про еду, стул и прогулку.
    ///
    /// **Пары взяты из того, ЧЕМ СЧИТАЛСЯ вердикт**, а не из соседних
    /// полей: последний выход, обычный промежуток между мочой, самый
    /// долгий. Поставь сюда что-нибудь другое — и человек будет читать
    /// факты, по которым вердикт не выводится, то есть проверить
    /// приложение ему станет нечем.
    ///
    /// `factLine` оставлена четвёртой строкой под разделителем, хотя
    /// на кадре её нет: это «ничего не надо вспоминать» — еда, стул
    /// и прогулка. Убрать её значило бы потерять содержание ради
    /// геометрии.
    private var фактыКарточка: some View {
        TGCard(spacing: Token.Space.s6) {
            фактСтрока("Последний выход",
                       signals.lastOutingAt.map { Fmt.clock($0) } ?? Self.нечегоСказать)
            фактСтрока("Обычный промежуток",
                       signals.typicalUrineInterval.map { Fmt.duration($0) } ?? Self.нечегоСказать)
            фактСтрока("Самый долгий",
                       signals.longestUrineInterval.map { Fmt.duration($0) } ?? Self.нечегоСказать)
            TGDivider()
            Text(verbatim: VerdictEngine.factLine(signals))
                .textStyle(AppFont.caption)
                .wraps()
        }
    }

    /// Тире вместо числа. Не «0» и не «нет данных»: ноль — это утверждение
    /// о собаке, выведенное из отсутствия записи, и ровно на нём Togo
    /// уже обжигался 28.09.
    private static let нечегоСказать = "—"

    private func фактСтрока(_ ключ: LocalizedStringKey, _ значение: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s12) {
            Text(ключ).textStyle(AppFont.caption).wraps()
            Spacer(minLength: Token.Space.s8)
            Text(verbatim: значение)
                .textStyle(AppFont.captionEmphasis)
                .multilineTextAlignment(.trailing)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: «Как попросил»

    /// Чипы прямо в шторке — вопрос задаётся ДО выхода, а не после.
    ///
    /// Ответ кладётся в `какПопросил` и уезжает в событие выхода
    /// в `startOuting()`. Не ответил — шторка `HowAskedSheet` открывается
    /// после записи, как раньше: вопрос остаётся незаданным, а чипы
    /// честно помечены «необязательно».
    @ViewBuilder
    private var какПопросилБлок: some View {
        if спрашиватьКакПопросил {
            TGSectionHeader(title: "как попросил · необязательно")
            TGChipGroup(items: AskSignal.allCases, title: \.title,
                        isSelected: { $0 == какПопросил }, minimumWidth: 130) { выбран in
                какПопросил = какПопросил == выбран ? nil : выбран
                Haptics.tap()
            }
        }
    }

    // MARK: Доза рядом с выходом

    /// Доза рядом с выходом — до того, как человек вышел.
    ///
    /// `WalkDose` был написан, покрыт тестами и **не вызывался
    /// ниоткуда**: механизм без места вызова от «работает»
    /// снаружи неотличим.
    ///
    /// Два ответа РАЗДЕЛЬНО, и это не удобство вёрстки: «доза
    /// через двадцать минут» и «можно дать на улице» — разные
    /// сообщения. Человеку с каплями в глаз надо сказать первое
    /// и НЕ сказать второе. Сведи их в один признак — получишь
    /// совет, неверный для половины случаев.
    ///
    /// **Кнопка «Дал» стоит ровно там же, где и ограничение:** она
    /// показывается только при `даётсяНаУлице`. Капли в глаз остаются
    /// строкой текста — про них сказано, и ничего не предложено.
    /// На кадре 07 кнопка белая (`action-primary`); здесь она
    /// `.finish`, потому что главное действие шторки одно и оно внизу.
    @ViewBuilder
    private var дозаБлок: some View {
        if let dog, let доза = WalkDose.рядом(dog) {
            TGCard {
                HStack(alignment: .center, spacing: Token.Space.s12) {
                    Image(systemName: "pills")
                        .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.medium))
                        .foregroundStyle(Token.Ink.link)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Token.Space.s2) {
                        Text(verbatim: дозаРядомТекст(доза))
                            .textStyle(AppFont.bodyEmphasis)
                            .wraps()
                        if доза.даётсяНаУлице {
                            // Тип назван явно. Тернарник из двух литералов
                            // выводится в `String`, а `Text(String)` рисует
                            // текст ДОСЛОВНО, мимо каталога: так 23.09
                            // французский экран оказался наполовину русским
                            // при полном каталоге.
                            let подпись: LocalizedStringKey = дозаОтмечена
                                ? "Отмечено · можно идти"
                                : "Эту можно дать на улице"
                            Text(подпись)
                                .textStyle(AppFont.caption)
                                .wraps()
                        }
                    }
                    Spacer(minLength: Token.Space.s8)
                    if доза.даётсяНаУлице, !дозаОтмечена {
                        TGButton(title: "Дал", variant: .finish, size: .medium,
                                 fullWidth: false) {
                            дать(доза)
                        }
                    }
                }
            }
        }
    }

    /// Отметить дозу прямо отсюда.
    ///
    /// Порядок тот же, что у «Сегодня», и он не переставляется:
    /// сперва отметка приёма (от неё считается окно натощак и защита
    /// от двойной дозы), пустой ответ останавливает всё; потом запись
    /// в ленте; и только после сохранения снимаются догоняющие
    /// напоминания. Снять их раньше значило бы оставить человека без
    /// напоминания о дозе, которая в хранилище не легла.
    private func дать(_ доза: WalkDose.Рядом) {
        guard let dog,
              let схема = dog.medications.first(where: { $0.id == доза.схемаID }),
              let отметка = DoseScheduler.markGiven(схема, scheduledAt: доза.когда,
                                                    by: appState.currentUserName,
                                                    context: context)
        else {
            Haptics.warning()
            appState.showFailure(String(localized: "Доза не отметилась · нажми ещё раз"))
            return
        }

        EventLog(context: context, appState: appState)
            .record(.dose, dog: dog, confirmation: "Записано · \(доза.препарат)") { event in
                event.note = доза.препарат
                event.medicationID = схема.id
            }

        ReminderScheduler.cancelDose(отметка)
        // Напоминания считаются от настоящего «сейчас», а не от часа
        // дозы по расписанию.
        Task { await ReminderScheduler.refresh(dog: dog, settings: settings, at: Date()) }
        дозаОтмечена = true
    }

    // MARK: Выход

    private func startOuting() {
        guard let dog,
              let event = EventLog(context: context, appState: appState)
                  .record(.outing, dog: dog, confirmation: nil)
        else { return }

        // Ответ чипами уезжает в ту самую запись, которую он описывает.
        // Пока записи не было, положить его было некуда — поэтому он
        // и жил в состоянии шторки.
        if let какПопросил {
            event.askSignal = какПопросил
        }

        appState.startOuting(by: appState.currentUserName)
        // Пометка стоит на строке самой подстановки, а не под вызовом:
        // сторож смотрит ту же строку и строку ВЫШЕ (`помечена(строка:в:)`),
        // а строку ниже не смотрит вовсе. Когда у вызова появился
        // аргумент `кобель:`, строка переехала — и пометка осталась
        // под подстановкой, то есть там, где её никто не ищет.
        LiveActivityController.startWalk(dogName: dog.name,  // кличка-в-слот: вход живой активности кормит и именительный ярлык, и винительные подписи — падеж знает слот
                                         by: appState.currentUserName, at: event.date,
                                         кобель: dog.sex == .male)

        // Спрашиваем не каждый раз: только при смене сигнала или раз в пять
        // выходов. Ответил чипами — второй раз не спрашиваем.
        if какПопросил == nil, Diary.shouldAskHowAsked(dog.events) {
            askSignal = true
        } else {
            appState.showUndo(String(localized: "Записано · Выход"), eventID: event.id)
            dismiss()
        }
    }
}

/// Один тап, который меняет поведение. Дверь откроется — то, что он сделал,
/// закрепится; приложение обязано спросить, что именно это было.
///
/// **Остаётся запасным путём после редизайна 23.10.2026.** Кадр 07 перенёс
/// тот же вопрос чипами в саму шторку «Просится», и человек, ответивший
/// там, сюда не попадает. Попадает тот, кто чипы пропустил: вопрос ему
/// по-прежнему не задан, и правило `Diary.shouldAskHowAsked` говорит,
/// что задать его надо.
struct HowAskedSheet: View {
    let dog: Dog?
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        TGSheet(
            title: "Как попросил?",
            subtitle: "Дверь откроется — то, что он сделал, закрепится. Отметь, и приложение покажет, если что-то идёт не туда."
        ) {
            VStack(spacing: Token.Space.s8) {
                ForEach(AskSignal.allCases, id: \.self) { signal in
                    Button { record(signal) } label: {
                        HStack(spacing: Token.Space.s12) {
                            Image(systemName: signal.symbol)
                                .font(.system(size: Token.Size.iconMd, weight: .medium))
                                .foregroundStyle(signal.isCalm ? Token.Action.doneText : Token.Ink.silhouette)
                                .frame(width: Token.Space.s24)
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(signal.title).textStyle(AppFont.body).foregroundStyle(Token.Ink.primary)
                                if signal == .satAtDoor {
                                    Text("то, что учим").textStyle(AppFont.micro).foregroundStyle(Token.Action.doneText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                        .padding(.horizontal, Token.Space.s14)
                        .background(Token.Surface.card, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TGExplainer(text: "Спрашиваем не каждый раз: только когда сигнал меняется или раз в несколько выходов.", памятка: "просится.неКаждыйРаз")
        }
        // Пять строк по 44 + шапка с подзаголовком в три строки — это
        // больше половины экрана уже на обычном кегле (оценка по
        // исходнику, кадра нет): на одном `.medium` последний ответ
        // и пояснение достаются только прокруткой внутри половинки,
        // а поднять шторку нельзя. Второй упор даёт дотянуть её вверх.
        .presentationDetents([.medium, .large])
    }

    private func record(_ signal: AskSignal) {
        if let dog, let last = Diary.last(dog.events, kind: .outing) {
            last.askSignal = signal
        }
        Haptics.tap()
        dismiss()
        onDone()
    }
}
