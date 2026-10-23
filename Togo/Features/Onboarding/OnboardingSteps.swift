import SwiftUI
import SwiftData

// Экраны шагов онбординга. Сам порядок шагов и черновик собаки живут
// в `OnboardingFlow` — здесь только то, что человек видит на каждом шаге.
//
// Редизайн iOS 28 «Кино», 23.10.2026: шагов стало четыре вместо шести.
// Что снято и почему — в голове `OnboardingFlow`, там же названо
// и то, чего из макета здесь нет.

/// Приветствие — эталон `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/18.png`.
///
/// Снизу вверх по кадру: **две** кнопки, подзаголовок «Дневник собаки
/// для всей семьи.», логотип «Togo», и всё это поверх фотографии
/// во весь экран.
///
/// **Кадр `18.png` переснят 23.10.2026 (пакет 6, `401e496`) и годен.**
/// Прежняя его редакция показывала три кнопки и ленту цитат — то есть
/// отменённое решением Виктории того же дня, — и около часа была ложным
/// эталоном. Если у кого-то на руках старая копия, сверять число кнопок
/// по ней нельзя; разбор — `ПОДПИСИ.md` того же каталога, раздел
/// «Поправка к собственной записи». Кадр приёмки с нашей стороны —
/// `Дизайн/кадры-приёмки/без-выдуманных-отзывов-23.10/`.
///
/// # Чем этот экран отличается от кадра, и это не забывчивость
///
/// ```
/// фото во весь экран      нет: плейсхолдеры Unsplash в продукт
///                         не включаются (README пакета), а своего
///                         фото у человека на первом запуске нет
///                         по построению. Вместо него иллюстрация
///                         «линия», сцена `onboarding`
/// лента цитат семей       УБРАНА ИЗ v1 решением 23.10.2026:
///                         выдуманные отзывы — App Review 2.3.1/3.1
/// кнопка «С примером»     УБРАНА ИЗ v1 тем же решением: демо-дневник
///                         это спринт (своё хранилище, «семья его
///                         не видит», выход без следов), а ценность
///                         до первого выхода с собакой низкая
/// «Меня позвали» белым    подпись берёт `Token.Ink.secondary`
///                         (вариант `.quiet` под стеклом). Белая
///                         подпись у кнопки без заливки — это роль,
///                         которой в `TGButton` нет, а `DesignSystem`
///                         этой смене не открыт
/// ```
///
/// **Кнопок на этом экране ровно две: «Начать» и «Меня позвали».**
/// Третья не «не нарисована» — она снята решением, и условия её
/// возврата лежат в `Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`, раздел «Убрано из v1
/// по App Review», а не в этом комментарии: макет его не читает.
struct WelcomeStep: View {
    var isReplay: Bool = false
    var onNext: () -> Void
    /// Вход ветки «меня позвали» — второй путь с первого же экрана.
    ///
    /// До 14.10.2026 его не было вовсе: приглашённый шёл онбордингом
    /// владельца и заводил **свою** собаку. Решение Виктории, принятое
    /// рисунком в макете: «своей собаки не создаём».
    ///
    /// Необязательное замыкание, а не обязательное, нарочно: при
    /// перечитывании (`isReplay`) ветка не показывается — человек
    /// с дневником уже не «позванный», и предлагать ему чужой
    /// дневник значит звать его туда, откуда он не вернётся
    /// без потери своего.
    var onJoin: (() -> Void)?

    /// Иллюстрация прячется на крупном кегле.
    ///
    /// Не «для красоты»: экран собран без прокрутки — так он собран
    /// в макете, — и на AX-ступенях текст с тремя кнопками занимает
    /// высоту целиком. Рисунок, оставленный там же, выдавил бы кнопки
    /// за нижний край, и человек с крупным шрифтом не нашёл бы
    /// «Начать» вовсе.
    @Environment(\.dynamicTypeSize) private var кегль

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s10) {
            if !кегль.isAccessibilitySize {
                Spacer(minLength: 0)
                TGIllustration(scene: .onboarding)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)

            Text("Togo").textStyle(AppFont.wordmark)
            Text("Дневник собаки для всей семьи.")
                .textStyle(AppFont.body.color(Token.Ink.secondary))
                .wraps()
                .padding(.bottom, Token.Space.s8)

            TGButton(title: isReplay ? "Перечитать" : "Начать",
                     action: onNext)
            // Вторая дорога, а не вторая кнопка того же действия:
            // «Начать» заводит СВОЙ дневник, «Меня позвали» —
            // присоединяет к чужому. Форма у них разная нарочно
            // (белая заливка против стекла), потому что два одинаково
            // выглядящих действия на одном экране мы уже проходили:
            // 22.09 человек нажал видимое «Пригласить человека»
            // и завёл участника вместо приглашения.
            if !isReplay, let onJoin {
                TGButton(title: "Меня позвали", variant: .quiet,
                         size: .medium, action: onJoin)
                    .стекло(радиус: Token.Radius.capsule)
            }
            Text("Всё считается на телефоне. Аккаунт не нужен.")
                .textStyle(AppFont.micro)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.bottom, Token.Space.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Token.Surface.screen.ignoresSafeArea())
    }
}

// MARK: - Шаг 1 · кличка и вес

/// Кличка и вес, и больше ничего.
///
/// **Порода, пол, кастрация и дата рождения сняты** — в макете iOS 28
/// на этом шаге их нет. Они не потеряны: те же поля стоят в профиле
/// собаки, и заполняются там в любой момент. Онбординг спрашивает
/// ровно то, без чего не работает ни одна подсказка: кличку, чтобы
/// звать собаку по имени, и вес, из которого считается порция
/// и сбор в дорогу.
struct DogStep: View {
    @Binding var draft: DogDraft
    var onNext: () -> Void
    /// Пропустить собаку. Есть не всегда: при повторном прохождении
    /// пропускать нечего — собака уже заведена.
    var onSkip: (() -> Void)?

    /// Фокус поля веса — единственного `.decimalPad` на этом шаге.
    @FocusState private var весВФокусе: Bool

    var body: some View {
        TGScreen(title: "Кто у тебя живёт") {
            // **Подсказка — слово «Кличка», а НЕ кличка.** До 23.10.2026
            // здесь стояло `TextField("Стич", …)`, и это уезжало
            // в каталог ключом: `TextField(_ titleKey:)` принимает
            // `LocalizedStringKey`, поэтому ЛЮБОЙ литерал-подсказка
            // переводится (замер: 47 из 47). Кличка Стич переводилась
            // как «Stitch»/«Стіч», а у человека, назвавшего собаку
            // так же, совпадало с ключом и переводилось уже его
            // СОБСТВЕННОЕ слово — живой отзыв `AEXYTDmy` «Где-то stitch
            // а где то Стич».
            //
            // Решение требовало «не кличка», и исполнено оно должно
            // быть именно так, а не «другая кличка»: другая кличка —
            // тот же класс, просто ещё не встреченный.
            TGCard {
                TextField("Кличка", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .textStyle(AppFont.screenTitle.weight(Token.FontWeight.medium))
                    .frame(minHeight: Token.Size.capsule)
            }

            TGCard {
                HStack(spacing: Token.Space.s12) {
                    шаг(значок: "minus", на: -0.1)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: Token.Space.s6) {
                        // Поле ввода, а не только шаговик, и это замер,
                        // а не вкус: в прототипе вес меняется ТОЛЬКО
                        // кнопками по 0,1 кг от 8,4. Для сорокакилограммовой
                        // собаки это триста с лишним нажатий, а такие
                        // собаки у нас в отзывах есть. Шаговик оставлен
                        // для подгонки, ввод — для первого числа.
                        // `.fixedSize()` — по кадру приёмки 23.10.2026.
                        // Без него поле жадно забирает всю ширину между
                        // кнопками, число встаёт по центру, а «кг»
                        // уезжает к плюсу: на кадре они читались как две
                        // разные вещи, а не как «4,1 кг». Ширина берётся
                        // от содержимого, то есть от подсказки, пока
                        // не введено своё.
                        TextField("4,1", text: $draft.weight)
                            .keyboardType(.decimalPad)
                            .focused($весВФокусе)
                            .multilineTextAlignment(.trailing)
                            .fixedSize()
                            .textStyle(AppFont.numeric(Token.FontSize.poster,
                                                       weight: Token.FontWeight.light))
                            .accessibilityLabel("Вес")
                        Text("кг").textStyle(AppFont.body.color(Token.Ink.secondary))
                    }
                    Spacer(minLength: 0)
                    шаг(значок: "plus", на: 0.1)
                }
                Text("Для порции и сборов в дорогу.")
                    .textStyle(AppFont.caption)
                    .wraps()
            }
        }
        // **Низ отдан системе, а не слоту `TGScreen`, и только здесь.**
        //
        // Слот каркаса считает запас от высоты САМОЙ панели
        // (`TGScaffolds.swift` `запасПодНизом = высотаНиза + s24`),
        // а панель в нём — сосед по `ZStack`, не inset. Клавиатура
        // поднимает панель и высоту её не меняет: запас остаётся
        // прежним, и содержимое уходит под панель. Замер с кадра:
        // `minY` панели 446 против 772 у экрана без клавиатуры,
        // Δ 326 pt содержимого недостижимо даже полной прокруткой.
        //
        // `safeAreaInset` складывается с клавиатурной безопасной
        // областью, поэтому запас растёт вместе с ней сам.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Token.Space.s8) {
                TGButton(title: "Дальше", isEnabled: draft.isValid, action: onNext)
                if let onSkip {
                    Button("Пока без собаки", action: onSkip)
                        .textStyle(AppFont.caption)
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
                }
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
            .padding(.bottom, Token.Space.s8)
        }
        // Выход с цифровой клавиатуры. У `.decimalPad` нет клавиши
        // возврата, и до 15.10 убрать её на этом шаге было нечем:
        // человек, набравший вес, упирался в экран, у которого две
        // последние строки формы под панелью.
        .готовоНадКлавиатурой { весВФокусе = false }
    }

    /// Круглая кнопка подгонки веса.
    ///
    /// Шаг 0,1 кг — как в макете. Нижняя граница 0,1, а не 0: вес нуль
    /// это не «маленькая собака», это «веса нет», и порция от него
    /// посчиталась бы нулевой.
    ///
    /// **Пока поле пусто, кнопки выключены, и это не придирка.**
    /// Шаговик подгоняет число, которое уже есть; от пустоты «плюс»
    /// дал бы 0,1 кг — то есть ПОДСТАВИЛ БЫ ВЕС, которого человек
    /// не называл. Подставить 4,1 «для удобства» нельзя по той же
    /// причине, по которой у нас пусты время забора и норма с бланка:
    /// подсказку человек подтверждает, подстановку — нет, а вес
    /// потом читает врач.
    private func шаг(значок: String, на дельта: Double) -> some View {
        Button {
            guard let текущий = draft.weightValue else { return }
            draft.weight = Fmt.decimal(max(0.1, текущий + дельта))
            Haptics.tap()
        } label: {
            Image(systemName: значок)
                .font(.system(size: Token.Size.iconLg, weight: .semibold))
                // `Ink.secondary`, а НЕ `Ink.faint`: у последнего в его
                // же описании стоит «текстом и значками не красится
                // ни в каком кегле», и `InkContrastTests` это держит.
                .foregroundStyle(draft.weightValue == nil ? Token.Ink.secondary : Token.Ink.primary)
                .frame(width: Token.Size.controlM, height: Token.Size.controlM)
        }
        .disabled(draft.weightValue == nil)
        .стекло(радиус: Token.Radius.capsule)
        .accessibilityLabel(дельта > 0 ? "Больше" : "Меньше")
    }
}

// MARK: - Шаг 2 · режим дня

/// Режим одной фразой: сколько ест, когда встаёт, пьёт ли лекарства.
///
/// # Чем это отличается от прежнего шага и от макета
///
/// Прежде здесь стоял `ScheduleEditor` целиком — четыре карточки:
/// подъём и отбой, число кормлений, дневная норма в граммах, времена
/// кормлений. Макет iOS 28 сводит шаг к одной фразе с тремя
/// подчёркнутыми местами, и это снято не «для красоты»: человек
/// на третьей минуте знакомства не знает дневную норму в граммах,
/// а приложение всё равно сверит её с тем, как он кормит на самом
/// деле, и поправит.
///
/// ```
/// макет    «{кличка} ест 2 раза в день, ходит на улице,
///           лекарства не пьёт.» — сплошная фраза, слова подчёркнуты
/// здесь    три строки, у каждой вопрос и подчёркнутый ответ
/// ```
///
/// **Почему не сплошная фраза.** Подчёркнутое слово внутри абзаца —
/// цель касания размером со слово, а у нас записано «цели ≥ 44 pt».
/// Сделать её строкой — единственный способ соблюсти это, не ломая
/// перенос на длинной кличке.
///
/// **«ходит на улице» НЕ СДЕЛАНО, и дело не в вёрстке.** Такого поля
/// нет нигде: `пелёнк|лоток|ходит дома` — ноль вхождений во всём
/// дереве (замер 23.10.2026). Нарисовать выбор, которому некуда
/// записаться, значит завести вход без механизма. Вместо него —
/// подъём (`wakeMinuteOfDay`), из которого раскладываются кормления
/// и выходы, то есть место с дорогой.
///
/// **Граммы и отбой остались умолчанием** `ScheduleDraft` (120 г,
/// 23:00) и правятся в «Режиме дня» профиля. Это ровно то, что
/// получал человек, нажимавший «Дальше» не меняя полей, — то есть
/// почти каждый; разница в том, что теперь он их не видел. Названо
/// здесь, а не умолчано.
struct ModeStep: View {
    @Binding var draft: DogDraft
    @Binding var schedule: ScheduleDraft
    var onNext: () -> Void

    private var кличка: String { Fmt.dogNameOrFallback(draft.name) }

    var body: some View {
        TGScreen(title: "Режим дня") {
            TGCard(spacing: 0) {
                строка(вопрос: "Ест",
                       ответ: String(localized: "\(Fmt.times(schedule.mealsPerDay)) в день")) {
                    ForEach(Self.сколькоРаз, id: \.self) { сколько in
                        Button(.готовая(Fmt.times(сколько))) { schedule.mealsPerDay = сколько }
                    }
                }
                TGDivider()
                строка(вопрос: "Встаёт",
                       ответ: Fmt.clock(minuteOfDay: schedule.wakeMinuteOfDay)) {
                    ForEach(Self.подъём, id: \.self) { минута in
                        Button(.готовая(Fmt.clock(minuteOfDay: минута))) {
                            schedule.wakeMinuteOfDay = минута
                        }
                    }
                }
                TGDivider()
                строка(вопрос: "Лекарства",
                       ответ: draft.isOnTreatment ? String(localized: "пьёт")
                                                  : String(localized: "не пьёт")) {
                    Button("не пьёт") { draft.isOnTreatment = false }
                    Button("пьёт") { draft.isOnTreatment = true }
                }
            }

            TGExplainer(text: "Нажми подчёркнутое, чтобы поменять. Приблизительно — приложение сверит это с тем, как ты кормишь на самом деле, и поправит.")

            if draft.isOnTreatment {
                TGCard {
                    Text("Медкнижка включится").textStyle(AppFont.cardTitle)
                    Text("Появится вкладка «Здоровье», окно натощак и защита от двойной дозы. Препарат добавишь потом — схему и часы спросим там.")
                        .textStyle(AppFont.caption)
                        .wraps()
                }
            }
        } bottom: {
            TGButton(title: "Дальше", action: onNext)
        }
    }

    /// Сколько раз в день кормят. Четыре — потолок не наш: больше
    /// четырёх раз кормят щенков, и у них свой расчёт, которого
    /// в приложении пока нет.
    private static let сколькоРаз = [1, 2, 3, 4]

    /// Часы подъёма получасовым шагом с пяти до одиннадцати.
    /// Границы — не круглое число, а то, за чем режим перестаёт быть
    /// режимом: раньше пяти это смена, позже одиннадцати — не подъём.
    private static let подъём: [Int] = stride(from: 5 * 60, through: 11 * 60, by: 30).map { $0 }

    /// Строка «вопрос — подчёркнутый ответ».
    ///
    /// Вся строка целиком и есть цель касания: подчёркнуто слово,
    /// нажимается строка. Так и подпись читается как в макете,
    /// и цель остаётся не меньше `tapTarget`.
    private func строка<Пункты: View>(вопрос: LocalizedStringKey, ответ: String,
                                      @ViewBuilder пункты: () -> Пункты) -> some View {
        Menu {
            пункты()
        } label: {
            HStack(spacing: Token.Space.s12) {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(вопрос).textStyle(AppFont.caps).textCase(.uppercase)
                    Text(.готовая(ответ))
                        .textStyle(AppFont.cardTitle.color(Token.Ink.link))
                        .underline()
                        .wraps()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .foregroundStyle(Token.Ink.secondary)
                    .accessibilityHidden(true)
            }
            // Воздух по вертикали — по кадру приёмки 23.10.2026: без него
            // `minHeight` не делает ничего (две строки, 20 + 14, и так
            // выше сорока четырёх), разделитель прилипает к подчёркнутому
            // ответу, и три строки читаются как одна слипшаяся.
            .padding(.vertical, Token.Space.s10)
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Строка «подпись — поле». Вынесена, потому что повторяется на трёх экранах.
///
/// Подпись отдаётся полю и как accessibility-имя: без этого VoiceOver
/// называет поле плейсхолдером («4,1», «+33…»), а два телефона подряд
/// на экране «Если что-то случилось» звучат одинаково.
/// `spokenLabel` — для случаев, когда видимая подпись коротка нарочно
/// («Телефон» под заголовком «Ветеринар»), а вслух нужна полная.
///
/// > **`ViewThatFits` отсюда СНЯТ 23.10.2026** — он запрещён красной
/// > линией проекта: держал в дереве обе раскладки, и озвучка находила
/// > две копии поля. Раскладка выбирается явным `if`
/// > по `dynamicTypeSize`, как в `UndoToastView` и `TGListRow`.
/// >
/// > Прежняя редакция этой головы говорила, что снять его «нельзя
/// > попутно: `LabeledField` зовут девятнадцать мест в `Health`,
/// > `Family` и `Profile`». **Довод был не про тот предмет.** Подпись
/// > типа не меняется ни на символ — меняется только внутренняя
/// > раскладка, — поэтому места вызова не правятся вовсе, и открытость
/// > их каталогов для этой замены не требуется. Девятнадцать вызовов
/// > были доводом за приёмку кадром, а не против починки.
struct LabeledField<Content: View>: View {
    /// Настройка размера текста: от неё зависит, строкой или столбцом
    /// раскладывать подпись и поле.
    @Environment(\.dynamicTypeSize) private var размерТекста

    let label: String
    var spokenLabel: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if размерТекста.isAccessibilitySize {
                // При крупной системной настройке подпись и поле
                // перестают помещаться рядом — тогда поле уезжает под
                // подпись, а не сжимается в щель.
                VStack(alignment: .leading, spacing: Token.Space.s4) {
                    Text(label).textStyle(AppFont.caption)
                    content
                        .multilineTextAlignment(.leading)
                        .textStyle(AppFont.body)
                        .accessibilityLabel(spokenLabel ?? label)
                }
            } else {
                HStack {
                    Text(label).textStyle(AppFont.body).fixedSize()
                    Spacer(minLength: Token.Space.s12)
                    content
                        .multilineTextAlignment(.trailing)
                        .textStyle(AppFont.body)
                        .accessibilityLabel(spokenLabel ?? label)
                }
            }
        }
        .frame(minHeight: Token.Size.tapTarget)
    }
}

// MARK: - Шаг 3 · разрешение на уведомления

/// Разрешение спрашиваем не на старте, а когда уже понятно, за что оно.
/// Отказ ничего не ломает: дневник работает целиком без уведомлений.
///
/// # Третьей строки макета здесь нет, и это запрет, а не пропуск
///
/// Прототип показывает три строки: «Доза по часам», «Окно натощак»
/// и **«Тревога · кровь, рвота — со звуком»**. Третьей дороги в коде
/// НЕТ: у `NotificationCenterService.Category` четыре случая —
/// `morningBrief`, `dose`, `fasting`, `escalation`, — и тревоги среди
/// них нет вовсе (замер 23.10.2026). Нарисовать её значило бы обещать
/// уведомление, которое не придёт в тот единственный раз, когда оно
/// нужнее всего.
///
/// Поэтому третьей строкой остаётся лестница эскалации — у неё
/// категория есть. **Её подпись не тронута ни словом, и это тоже
/// решение:** «сначала дежурному, потом остальным» обещает адресатов,
/// а пуши у нас локальные (`CKSubscription` — ноль вхождений). Долг
/// открыт, наряд — `docs/спринт-канал-эскалации.md`; усиливать
/// обещание нельзя, чинить его — не эта работа.
struct NotificationsPrimingStep: View {
    /// В просмотре — ложно, и тогда шаг ничего не меняет.
    ///
    /// Здесь не хранилище, а две вещи вне его, и обе необратимы
    /// по-своему: `notificationsAsked` в `UserDefaults` и **системный
    /// запрос разрешения**. Второй хуже: у человека он спросит
    /// по-настоящему, а в прогоне поднимет модальный алерт, который
    /// никто не ждёт и который останавливает весь дальнейший заход.
    var пишемВБазу: Bool = true
    var onDone: () -> Void

    @Environment(Settings.self) private var settings
    @State private var isRequesting = false

    var body: some View {
        TGScreen(title: "Что будет прерывать") {
            TGExplainer(text: "Прерывают ровно три вещи. Всё остальное ждёт утра — это единственный способ не превратить дневник в источник тревоги.")

            VStack(spacing: Token.Space.s8) {
                InterruptRow(symbol: "pills", title: "Доза по часам",
                             detail: "и то только если собака на лечении")
                InterruptRow(symbol: "clock.badge.exclamationmark", title: "Окно натощак",
                             detail: "еда внутри окна мешает всасыванию")
                InterruptRow(symbol: "bell.badge", title: "Лестница эскалации",
                             detail: "если дозу не отметили — сначала дежурному, потом остальным")
            }

            TGCard {
                Text("Одно напоминание в \(Fmt.clock(minuteOfDay: settings.briefHour * 60))").textStyle(AppFont.cardTitle)
                Text("Груминг, антипаразитарка, прививки, взвешивание — не восемь напоминаний, а одно в выбранный час. Час можно сдвинуть в настройках.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Разрешить", systemImage: "bell", isEnabled: !isRequesting) {
                Task { await request() }
            }
            // «Потом, в настройках», а не «Не сейчас»: дорога есть
            // и названа — «Настройки → Уведомления», оттуда же открывается
            // системный экран разрешений. Отказ без адреса читается как
            // «больше не спросят».
            TGButton(title: "Потом, в настройках", variant: .quiet, size: .medium) {
                if пишемВБазу { settings.notificationsAsked = true }
                onDone()
            }
        }
    }

    private func request() async {
        // В просмотре кнопка доводит до конца шага и ничего не просит:
        // спрашивать разрешение у человека, который зашёл посмотреть,
        // значит задать ему вопрос от его же имени.
        guard пишемВБазу else { return onDone() }
        isRequesting = true
        _ = await NotificationCenterService.requestAuthorization()
        settings.notificationsAsked = true
        isRequesting = false
        onDone()
    }
}

struct InterruptRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        TGCard(padding: Token.Space.s14) {
            TGIconRow(symbol: symbol, title: .готовая(title), detail: .готовая(detail),
                      tint: Token.Status.waitingText)
        }
    }
}

/// Конец повторного прохождения: ничего не создаём, просто выпускаем обратно.
struct HowItWorksReplayEnd: View {
    var onDone: () -> Void

    var body: some View {
        TGScreen(title: "Это всё") {
            TGCard {
                Text("Инструкция всегда под рукой").textStyle(AppFont.cardTitle)
                Text("Тот же текст всегда есть в «Настройки → Как это работает». Отдельной справки нет: объяснения стоят там, где возникает вопрос.")
                    .textStyle(AppFont.caption)
            }
        } bottom: {
            TGButton(title: "Вернуться к дневнику", action: onDone)
        }
    }
}
