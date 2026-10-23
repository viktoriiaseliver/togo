// Сгенерировано Tools/generate_tokens.py из DesignTokens/tokens.json.
// Не редактировать руками: правки перезапишет `make tokens`.
//
// Источник правды — tokens.json. Тот же файл импортируется в Figma
// как коллекции переменных, поэтому имена здесь и имена в Figma совпадают.

import SwiftUI

/// Токены Того. Экраны читают Semantic и Component; Primitive — только
/// внутри дизайн-системы.
nonisolated enum Token {

    /// Общие динамические цвета: ОДИН объект на одно значение.
    /// 
    /// `Color(Dyn(…))` делает `UIColor(dynamicProvider:)`, а два таких
    /// объекта с одинаковыми значениями НЕ РАВНЫ — равенство у
    /// динамического цвета по объекту, не по значению. Пока каждый
    /// токен получал свой `Dyn`, три утверждения `DesignTokenTests`
    /// падали на верных значениях: `Button.Primary.background ==
    /// Action.primary`, `Timeline.nowMarker == Action.primary`,
    /// `Button.Primary.label == Ink.onAccent`.
    /// 
    /// Переход на динамический цвет отнимает у токенов равенство
    /// по значению; сторож, выражающий правило через `==` двух
    /// токенов, краснеет не на правиле, а на устройстве цвета.
    /// Одно значение — один объект, и `==` снова означает «один токен».
    /// 
    /// ГРАНИЦА ЭТОЙ ПОЧИНКИ, названа `togo-05` 07.10.2026 и важнее
    /// её самой. Дедупликация СМЕНИЛА СМЫСЛ `==` между токенами:
    /// 
    ///     до   «это один и тот же токен»   (равенство объектов)
    ///     после «у них одинаковые четыре значения»
    /// 
    /// То есть `Token.A == Token.B` теперь зелено и когда роли
    /// РАЗНЫЕ, а значения совпали. Сторож на цвет через `==` может
    /// быть зелёным ПО ПРИЧИНЕ ДЕДУПЛИКАЦИИ, а не потому, что цвет
    /// верен — и отличить это по его виду нельзя.
    /// 
    /// Проверка по виду отвечает на вопрос, которого не задавали.
    /// Единственный честный путь спросить про сам цвет —
    /// `Color.resolvedHex(dark:highContrast:)`: он отдаёт то, что
    /// система даст тому, кто рисует, и в четырёх режимах порознь.
    fileprivate enum Общие {
        static let amber = Color(Dyn(dark: 0xF7C75F, light: 0x8A640F, darkHC: 0xF7C75F, lightHC: 0x6B4C0C))
        static let amberBg = Color(Dyn(dark: 0x4A300A, light: 0xFCEBCB, darkHC: 0x4A300A, lightHC: 0xFCEBCB))
        static let arctic = Color(Dyn(dark: 0xFFFFFF, light: 0x1F4FFF, darkHC: 0xFFFFFF, lightHC: 0x0E14A1))
        static let arcticInk = Color(Dyn(dark: 0x111111, light: 0xFFFFFF, darkHC: 0x111111, lightHC: 0xFFFFFF))
        static let arcticPressed = Color(Dyn(dark: 0xD1D1D6, light: 0x080679, darkHC: 0xD1D1D6, lightHC: 0x080679))
        static let arcticSubtle = Color(Dyn(dark: 0x5A5D61, light: 0xD9E3FC, darkHC: 0x5A5D61, lightHC: 0xD9E3FC))
        static let arcticTint = Color(Dyn(dark: 0xFFFFFF2E, light: 0x1F4FFF38, darkHC: 0xFFFFFF2E, lightHC: 0x0E14A138))
        static let clay = Color(Dyn(dark: 0xFF7A66, light: 0xAE2219, darkHC: 0xFFA696, lightHC: 0x9B100E))
        static let clayBg = Color(Dyn(dark: 0x4D1F22, light: 0xF7D5CF, darkHC: 0x4D1F22, lightHC: 0xF7D5CF))
        static let glass = Color(Dyn(dark: 0x1E1E2280, light: 0xFFFFFF9E, darkHC: 0x1E1E22D1, lightHC: 0xFFFFFF9E))
        static let glassCard = Color(Dyn(dark: 0x1C1C2094, light: 0xFFFFFFB8, darkHC: 0x242426E6, lightHC: 0xFFFFFFB8))
        static let glassEdge = Color(Dyn(dark: 0xFFFFFF47, light: 0xFFFFFFF2, darkHC: 0xFFFFFF66, lightHC: 0xFFFFFFF2))
        static let glassLine = Color(Dyn(dark: 0xFFFFFF1A, light: 0x0000000F, darkHC: 0xFFFFFF38, lightHC: 0x0000000F))
        static let glassShadow = Color(Dyn(dark: 0x00000073, light: 0x14192824, darkHC: 0x00000073, lightHC: 0x14192824))
        static let glassStrong = Color(Dyn(dark: 0x141418CC, light: 0xFFFFFFDB, darkHC: 0x141418F0, lightHC: 0xFFFFFFDB))
        static let hairline = Color(Dyn(dark: 0x3A3A3C, light: 0xD6D9DD, darkHC: 0x6D6D72, lightHC: 0x7D8085))
        static let indigo = Color(Dyn(dark: 0x1F4FFF, light: 0x1F4FFF, darkHC: 0x1F4FFF, lightHC: 0x0E14A1))
        static let indigoSubtle = Color(Dyn(dark: 0x2C3A66, light: 0x2C3A66, darkHC: 0x3A4C85, lightHC: 0x2C3A66))
        static let ink = Color(Dyn(dark: 0xFFFFFF, light: 0x101112, darkHC: 0xFFFFFF, lightHC: 0x101112))
        static let inkFaint = Color(Dyn(dark: 0x8E8E93, light: 0xA1A4A8, darkHC: 0xAEAEB2, lightHC: 0x7D8085))
        static let inkMuted = Color(Dyn(dark: 0xC7C7CC, light: 0x5A5D61, darkHC: 0xEBEBF0, lightHC: 0x45484C))
        static let link = Color(Dyn(dark: 0xA2C1FE, light: 0x1F4FFF, darkHC: 0xC2D6FF, lightHC: 0x0E14A1))
        static let night1 = Color(Dyn(dark: 0x000000, light: 0xFFFFFF, darkHC: 0x000000, lightHC: 0xFFFFFF))
        static let night2 = Color(Dyn(dark: 0x1C1C1E, light: 0xECEDF0, darkHC: 0x242426, lightHC: 0xECEDF0))
        static let night3 = Color(Dyn(dark: 0x2C2C2E, light: 0xE3E5E8, darkHC: 0x363638, lightHC: 0xE3E5E8))
        static let night4 = Color(Dyn(dark: 0x3A3A3C, light: 0xFFFFFF, darkHC: 0x48484A, lightHC: 0xFFFFFF))
        static let night5 = Color(Dyn(dark: 0x3A3A3C, light: 0xD7DBE0, darkHC: 0x48484A, lightHC: 0xD6D9DD))
        static let nightControlPressed = Color(Dyn(dark: 0x48484A, light: 0xD7DBE0, darkHC: 0x5A5A5E, lightHC: 0xD6D9DD))
        static let nightPage = Color(Dyn(dark: 0x0A0A0B, light: 0xFFFFFF, darkHC: 0x000000, lightHC: 0xFFFFFF))
        static let posterAmber = Color(Dyn(dark: 0x4A3A14, light: 0x8A640F, darkHC: 0x4A3A14, lightHC: 0x8A640F))
        static let posterClay = Color(Dyn(dark: 0x5E2A22, light: 0xB5402F, darkHC: 0x5E2A22, lightHC: 0xB5402F))
        static let posterIndigo = Color(Dyn(dark: 0x2A3670, light: 0x3F5BC4, darkHC: 0x2A3670, lightHC: 0x3F5BC4))
        static let posterInk = Color(Dyn(dark: 0xF4F4F2, light: 0xFFFFFF, darkHC: 0xF4F4F2, lightHC: 0xFFFFFF))
        static let posterInkMuted = Color(Dyn(dark: 0xB2B2AE, light: 0xFFFFFFE0, darkHC: 0xC8C8C4, lightHC: 0xFFFFFF))
        static let scrim = Color(Dyn(dark: 0x0000008C, light: 0x10111252, darkHC: 0x0000008C, lightHC: 0x10111252))
        static let spruceText = Color(Dyn(dark: 0x7FD3A8, light: 0x286B4C, darkHC: 0x7FD3A8, lightHC: 0x215940))
        static let stockLow = Color(Dyn(dark: 0xFFA15C, light: 0xB85400, darkHC: 0xFFA15C, lightHC: 0xA34A00))
        static let stockLowBg = Color(Dyn(dark: 0x4A2A10, light: 0xFFEBD9, darkHC: 0x4A2A10, lightHC: 0xFFEBD9))
    }

    /// Поверхности: бумага, карточка, утопленное, хайрлайн.
    enum Surface {
        static let card = Общие.night2
        /// Плашка контрола. РАЗВЕДЕНА С `sunken` 23.10.2026 ответом дизайна: «`surface-control` #3A3A3C, нажатие #48484A. `surface-sunken` остаётся #2C2C2E. Совпадение не задумано». До этого дня обе роли давали в тёмной #2C2C2E байт в байт, и утопленная область с плашкой контрола были на экране неразличимы. Двигалась ТОЛЬКО эта роль: `semantic.surface.sunken` не тронут ни одним символом, 20 его вхождений в Swift стоят как стояли.
        static let control = Общие.night4
        /// Нажатая плашка контрола (`cinema.surface.controlPressed`). Заведена 23.10.2026 ответом дизайна. ЧИТАТЕЛЕЙ В SWIFT НОЛЬ — названо здесь нарочно, чтобы роль не выглядела подключённой: ни одно из четырёх мест показа `Surface.control` нажатого состояния не рисует. Подробности и единственный готовый претендент — в `primitive.color.nightControlPressed`.
        static let controlPressed = Общие.nightControlPressed
        /// Стекло таббара и круглых кнопок
        static let glass = Общие.glass
        /// Внутренний край стекла
        static let glassEdge = Общие.glassEdge
        static let hairline = Общие.hairline
        /// Полотно под фоном-фото. От `screen` отличается одним шагом светлоты — стык затемнения фото и полотна виден глазом. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let page = Общие.nightPage
        static let pressed = Общие.night5
        /// Приподнятая сплошная поверхность — и ЗАМЕНА СТЕКЛА при Reduce Transparency (рекомендация 7 хендоффа). Единственный читатель, ради которого роль заведена: `TGGlass`. Совпадает по значению с `sunken`, но роль обратная, и разводить их именами обязательно: `sunken` уходит вглубь, `raised` всплывает. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let raised = Общие.night3
        static let screen = Общие.night1
        /// Затемнение под шторкой
        static let scrim = Общие.scrim
        static let sunken = Общие.night3
    }

    /// Текст. `faint` — 2,5:1, текстом и значками НЕ красится ни в каком кегле: разрешение «только с 14pt» было неверным и развело его по двадцати четырём файлам.
    enum Ink {
        static let faint = Общие.inkFaint
        /// Ссылка (`cinema.text.link`). Индиго ЗДЕСЬ ОСТАЛОСЬ: отменён индиговый АКЦЕНТ, а не значение. Акцент теперь белый, ссылка — нет. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let link = Общие.link
        static let onAccent = Общие.arcticInk
        /// Тихий текст НА акцентной заливке: счётчик под подписью кнопки, подпись под показанием. Заведён 08.10.2026, потому что у роли не было адреса в семантике и единственным носителем значения был poster/captionOnDose — то есть кнопка режима прогулки обращалась бы к токену ПЛАКАТА. Значение то же (arcticSubtle), роль другая, и имя должно называть роль. Числа: 6,19:1 в тёмной и 10,01:1 в светлой против 10,43 и 12,86 у onAccent — читается и остаётся тише подписи, иерархия цела. Повышенного контраста у роли в пакете нет: darkHC равен dark.
        static let onAccentQuiet = Общие.arcticSubtle
        static let primary = Общие.ink
        static let secondary = Общие.inkMuted
        static let silhouette = Общие.inkMuted
    }

    /// Действия. Охряная кнопка строго одна на экран.
    enum Action {
        static let done = Color(hex: 0x5FBF9326)
        static let doneQuiet = Color(hex: 0x5FBF9326)
        /// «Сделано» СЛОВАМИ. Отдельный токен, потому что done — это тинт 15 %: как чернила он даёт 1,31:1 на карточке, вдвое хуже уже запрещённого faint. Та же пара, что waitingText и overdueText.
        static let doneText = Общие.spruceText
        /// Подпись на тихой заливке (`cinema.action.onSubtle` = #FFFFFF). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let onSubtle = Общие.posterInk
        static let primary = Общие.arctic
        /// Нажатое главное действие
        static let primaryPressed = Общие.arcticPressed
        static let primaryQuiet = Общие.arcticTint
        static let secondary = Общие.night4
        /// Тихая индиговая заливка второй кнопки (`cinema.action.subtle`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let subtle = Общие.indigoSubtle
    }

    /// Состояния: янтарь — «подожди», терракот — просрочка или кровь.
    enum Status {
        static let doneBg = Color(hex: 0x5FBF9326)
        static let doneText = Общие.ink
        static let overdueBg = Общие.clayBg
        static let overdueText = Общие.clay
        /// Запас кончается — плашка. ≤ 7 дней; ≤ 3 берёт overdue
        static let stockLowBg = Общие.stockLowBg
        /// Запас кончается — текст и значок. Заведён 05.10 вечером вторым шагом: примитив положили в tokens.json, а семантического имени не дали — и в Tokens.generated.swift его не оказалось ВОВСЕ. Генератор поднимает в Swift то, на что ссылается семантика; примитив без алиаса до слоя вида не доезжает. Нашёл togo-9e, искавший, чем покрасить уровень .low. ПРАВКА 07.10 вечер, togo-1e: у лестницы запаса ЧЕТЫРЕ ступени (PillSupplyAdvisor.Level: ok · low · urgent · out), а статусных цветов три. Ступень .out («кончилось») красится ТЕМ ЖЕ терракотом, что .urgent, и это решение, а не недосмотр: четвёртого статусного цвета у системы нет, и заводить его ради одной ступени нельзя — различать «пора покупать» и «уже нечего дать» обязано СЛОВО. У нас записано, что срочность не передаётся одним цветом; здесь то же правило с другой стороны — раз цвет не различает, различает текст. Заведёшь пятый цвет под .out — сначала проверь, что слова не хватило.
        static let stockLowText = Общие.stockLow
        static let waitingBg = Общие.amberBg
        static let waitingText = Общие.amber
    }

    /// Отступы.
    enum Spacing {
        static let cardPadding: CGFloat = 16
        static let screenPadding: CGFloat = 18
        static let stack: CGFloat = 12
    }

    /// Радиусы.
    enum Radius {
        /// Пилюля: главное действие, чип, тост, поле. Семантическое имя заведено 05.10 вечером ВТОРЫМ заходом — primitive.radius.capsule уже стоял 999, а Token.Radius.capsule не существовал, и сторож, написанный на него, уронил сборку. Тот же промах, что часом раньше со stockLow: генератор поднимает в Swift семантику, примитив без алиаса до слоя вида не доезжает
        static let capsule: CGFloat = 999
        static let card: CGFloat = 24
        static let control: CGFloat = 24
        /// Радиус нижних углов плаката. Макет: border-radius: 0 0 44px 44px.
        static let poster: CGFloat = 44
        static let sheet: CGFloat = 36
        static let small: CGFloat = 12
        static let tile: CGFloat = 16
    }

    /// Стекло. **Значения отсюда — не то, чем рисуют.** Рекомендация 1 хендоффа iOS 28: стекло — системные материалы (`glassEffect`), а не свои rgba. Эти токены нужны веб-макету и запасному пути на iOS 17–25; Reduce Transparency не берёт отсюда ничего и уходит на `Surface.raised` без блюра. Один читатель на все три пути — `TGGlass`.
    enum Glass {
        /// Радиус размытия запасного пути.
        static let blur: CGFloat = 30
        /// Карточка-стекло.
        static let card = Общие.glassCard
        /// Верхний блик, 1px inset.
        static let highlight = Общие.glassEdge
        /// Разделитель внутри стекла.
        static let line = Общие.glassLine
        /// Насыщенность запасного пути. ЧИСЛО, А НЕ РАЗМЕР: `.saturation(_:)` принимает долю, и 1,9 в точках не существует.
        static let saturation: Double = 1.9
        /// Тень плавающего.
        static let shadow = Общие.glassShadow
        /// Плотное стекло: панель показания.
        static let strong = Общие.glassStrong
    }

    /// Плакат — верхняя треть «Сегодня» и «На улице». Цвет блока = РЕЖИМ ДНЯ, и правило выбора в `TogoShared/Domain/PosterMode.swift`, не во вью: его спрашивают экран, виджет и «остров». Шторки плаката не несут.
    enum Poster {
        static let background = Общие.posterIndigo
        static let backgroundAlarm = Общие.posterClay
        /// Подложка плаката ЧАСА ДОЗЫ. С 22.10.2026 смотрит на `indigo`, а не на `arctic`: акцент стал белым, а тон дозы в хендоффе остался индиговым (`readingTone.dose.panel` rgba(31,79,255,.92)). В СВЕТЛЫХ режимах значение не изменилось ни на байт — там и было #1F4FFF / #0E14A1. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`. Плакат ЧАСА ДОЗЫ. И отдельно, потому что сверка с макетом без этого даёт ложный дефект: **это же значение — плакат ОНБОРДИНГА в макете Figma**. Замер 15.10.2026, побайтно: `Poster/Background` макета #A2C1FE/#1F4FFF = `arctic`; `Poster/Text` #0B0D2E/#FFFFFF = `arcticInk`; `Poster/On Action` и `Poster/Action` — та же пара. То есть онбординг стоит на АКЦЕНТЕ, и новых токенов плаката под него заводить НЕ НУЖНО — пара уже здесь. Две сессии 14.10 независимо прочли имя переменной макета `--poster-*` как роль и чуть не завели третью копию той же пары; разводить `semantic.poster.*` значило бы сделать это в третий раз. Наш `poster.background` (= `posterIndigo` #2A3670/#3F5BC4) — РЕЖИМ ДНЯ, другая роль, случайно похоже названная: 17 читателей и 45 вызовов `.posterHeader` в 33 файлах, трогать запрещено. ПРО lightHC: здесь #0E14A1, потому что следует за `arctic.lightHC`, который по решению Виктории 15.10 остался прежним. У макета повышенного контраста НЕТ ВОВСЕ — значит сверка этого режима с макетом невозможна, а не «расходится»: в HC наш плакат обязан быть грубее, и он грубее.
        static let backgroundDose = Общие.indigo
        static let backgroundFasting = Общие.posterAmber
        static let backgroundQuiet = Общие.night2
        /// Косточка обычного плаката. `readingTone.normal.bar` = #1F4FFF, то есть индиго, а не белый акцент. Переведена на `indigo` по той же причине, что подложка дозы. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`. 
        static let bar = Общие.indigo
        /// Подпись на косточке плаката дозы — по той же причине, что показание. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`. 
        static let barOnDose = Общие.posterInk
        /// ТОЛЬКО НЕЙТРАЛЬНЫЙ БЛОК. На цветных — captionOnColor, на дозе — captionOnDose. В светлой на синем блоке даёт 1,10.
        static let caption = Общие.inkMuted
        /// Подпись плаката на ЦВЕТНОМ блоке.
        static let captionOnColor = Общие.posterInkMuted
        /// Тихая подпись на плакате дозы. Было `arcticSubtle`, который переехал на белую заливку (#5A5D61) и на индиго дал бы 1,5:1. ЭТО ТО САМОЕ САМОЕ УЗКОЕ МЕСТО, про которое в описании `arctic` записано «запас одна сотая»: прежняя пара давала 4,51 при пороге 4,5. Новая пара меряется заново — см. `Tools/contrast_graphite.py`, раздел «ПАРЫ РЕПОЗИТОРИЯ». Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`. Подпись плаката на заливке дозы. Отдельная от caption потому, что доза — единственный режим дня со СВЕТЛОЙ подложкой: остальные четыре кладут текст на тёмный блок, и там caption честен. У плаката ПАКЕТА режима дозы нет вовсе — его bg всегда тёмный блок с белым текстом, — то есть инверсия наша, и цена её в том, что для неё нужен свой тихий цвет.
        static let captionOnDose = Color(hex: 0xFFFFFFE0)
        /// ТОЛЬКО НЕЙТРАЛЬНЫЙ БЛОК (backgroundQuiet). На цветных блоках берётся labelOnColor, на дозе labelOnDose: у плаката ТРИ семьи текста, а не одна. Замер 07.10.2026: этот токен на синем блоке в светлой даёт 3,15 — он честен только там, где подложка нейтральна.
        static let label = Общие.ink
        /// Заголовок плаката на ЦВЕТНОМ блоке: обычный, тревожный, натощак.
        static let labelOnColor = Общие.posterInk
        /// Показание на плакате дозы. Было `arcticInk`, который стал #111111 — чёрная подпись на индиго нечитаема. `readingTone.dose.fg` = #FFFFFF, и `posterInk` ровно эта роль: текст НА ЦВЕТНОМ блоке. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`. 
        static let labelOnDose = Общие.posterInk
    }

    /// Шаг сетки. Прикладной код берёт Spacing, а не это.
    enum Space {
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s18: CGFloat = 18
        static let s2: CGFloat = 2
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let s4: CGFloat = 4
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
    }

    /// Размеры контролов и иконок.
    enum Size {
        static let avatarMd: CGFloat = 40
        static let avatarSm: CGFloat = 26
        /// Высота фона-фото на подэкране (`backdrop.height.sub`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let backdropSub: CGFloat = 360
        /// Высота фона-фото на вкладке (`backdrop.height.tab`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let backdropTab: CGFloat = 420
        /// Высота фона-фото на «Сегодня» (`backdrop.height.today`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let backdropToday: CGFloat = 640
        /// Высота фона-фото на «На улице» (`backdrop.height.walk`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let backdropWalk: CGFloat = 520
        /// Высота косточки прогресса на плакате. Макет: height 16px. ПАРЫ В ПАКЕТЕ НЕТ: среди size/ шестнадцати нет вовсе, а space/16, radius/inner и type/size/callout равны шестнадцати СЛУЧАЙНО — по роли они косточке не родня. Взять любое из них значило бы завести связь, которой нет, и в день, когда иконки станут 18, косточка поехала бы за ними без причины.
        static let bone: CGFloat = 16
        /// Главное действие — капсула 60 pt. Только оно
        static let capsule: CGFloat = 60
        /// Плитка действия. Было общим с главной кнопкой: один номер держал две роли, и «капсула 60 pt» из «Льда» растила заодно плитки
        static let controlL: CGFloat = 52
        static let controlM: CGFloat = 50
        static let controlXL: CGFloat = 54
        /// Радиус размытия стекла (`glass.blur`). ВНИМАНИЕ НА РАСХОЖДЕНИЕ ВНУТРИ ХЕНДОФФА: в токенах 30 и насыщенность 190 %, а в прозе README про панель показания — «блюр 28 / 180 %». Взято число из ТОКЕНОВ, потому что таблица «Источник правды» самого README называет источником файл токенов, а не прозу. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let glassBlur: CGFloat = 30
        static let hairline: CGFloat = 1
        static let handleH: CGFloat = 4
        static let handleW: CGFloat = 36
        /// Высота панели показания (`size.hero`). При крупном кегле — `heroAX` 220. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let hero: CGFloat = 360
        /// Высота панели показания при крупном кегле (`size.heroAX`). Отдельная ось: панель ужимается, чтобы кнопки низа остались на экране. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let heroAX: CGFloat = 220
        static let iconLg: CGFloat = 20
        static let iconMd: CGFloat = 16
        static let iconSm: CGFloat = 13
        /// Минимальная высота строки ленты (`size.rowMin`). Своим номером, а не общим с капсулой 60: один номер на две роли уже один раз растил плитки заодно с кнопкой. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let rowMin: CGFloat = 60
        /// Высота таб-бара, 4 вкладки (`size.tabBar`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let tabBar: CGFloat = 64
        /// Высота одной вкладки внутри бара (`size.tabItem`). Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let tabItem: CGFloat = 56
        static let tapTarget: CGFloat = 44
    }

    /// Кегли.
    enum FontSize {
        /// Строка списка
        static let body: CGFloat = 17
        /// Капс: название секции, 600
        static let caption: CGFloat = 14
        /// Крупная цифра карточки
        static let display: CGFloat = 34
        /// Ответ на главный вопрос — один на экран. НЕ поднят до 96px поколения «финал» нарочно: макет задаёт эту цифру С ОСЬЮ УСТРОЙСТВА — 96 на iPhone 402, 80 на SE 375 и развороте, 112 на iPad, — а оси устройства в наших токенах нет вовсе. Плоские 96 переполнили бы SE, то есть «исполнение макета» сломало бы узкий экран. Нужна ось, и это отдельная работа, а не правка значения
        static let hero: CGFloat = 56
        /// Мета: время, автор, подпись
        static let meta: CGFloat = 15
        /// Было 12. Ниже четырнадцати в системе не существует — и с 15.10.2026 это правило ИСПОЛНЯЕТСЯ, а не только записано. Решение Виктории того же дня, прямым вопросом: «Пол 14, макет поправить». ЧТО БЫЛО ДО: стиль `AppFont.micro` брал `font.size.meta` = 15px, то есть эту ступень в приложении НЕ ЗВАЛ НИКТО — живых читателей `Token.FontSize.micro` в Swift ноль. Решение было названо автором стиля в доккомментарии («мета сведена к пятнадцати»), но у него была неизмеренная цена: ступень УЕЗЖАЕТ ДИЗАЙНЕРУ — `--primitive-font-size-micro: 14px` в `tokens.css` и `font/size/micro` в `figma-variables.json` вместе с этим описанием, которое читает плагин в Фигме, — а доккомментарий Swift в Фигму не уезжает. Значит дизайнер, применивший `font/size/micro`, получал 14 в макете и 15 в приложении: одно имя, два значения, по разные стороны границы. ИСТОЧНИК ПРАВДЫ МОЖЕТ СОДЕРЖАТЬ РЕШЕНИЕ, КОТОРОГО НЕ ИСПОЛНЯЕТ НИ ОДИН ЧИТАТЕЛЬ, и грепом это не видно: имя находится, значение находится, а вызова по имени нет — опусти её назад до 12, и на экране не изменилось бы ничего. Теперь привязка сделана (`Typography.swift`, `AppFont.micro`), радиус 50 вызовов в 34 файлах, и держат её ДВА сторожа в `ПолКегляTests` — по значению и по имени в исходнике: проверка только по значению слепа к подмене равнозначной ступенью (`caption` тоже 14), и это доказано подделкой, а не предположено. Макет онбординга просит для подписей полей 12px (`onb/fs-caption`) — ровно то, что отсюда убрали; её решение «макет поправить», то есть 12 не возвращаем.
        static let micro: CGFloat = 14
        /// Заголовок шапки-плаката. Решение дизайна окт 2026: «формы, списки, онбординг, профиль, настройки — шапка-плакат (статус-бар, навигация, ЗАГОЛОВОК 40 ROUNDED, подзаголовок)». Сорока в шкале не было вовсе, и слой вида её дописать не может: `DesignLiteralTests` держит храповик на числа. Между `screen` 34 и `hero` 56 — не «посередине», а потому что так названо решением. В отличие от `hero`, оси устройства здесь не нужно: сорок помещаются и на SE 375
        static let poster: CGFloat = 40
        /// Название экрана
        static let screen: CGFloat = 34
        /// Заголовок карточки
        static let section: CGFloat = 20
        static let title: CGFloat = 17
        /// Крупный заголовок темы «Кино» (`cinema.titleLarge.size`). Ступень НОВАЯ: наш `screen` 34 не тронут, потому что у него свои читатели. Трекинг к ней — `primitive.font.tracking.titleLarge`. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let titleLarge: CGFloat = 36
        /// Таймер на «На улице» (`type.walkTimer.size`), SF Pro Rounded 300. Единственная ступень выше `hero` 56 — и единственное место, где она звана. Оси устройства у неё, как и у `hero`, нет. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let walkTimer: CGFloat = 76
    }

    /// Начертания.
    enum FontWeight {
        static let bold: Font.Weight = .bold
        /// Только SF Pro Rounded в главной цифре, кличке и заголовке экрана
        static let heavy: Font.Weight = .heavy
        /// Крупные цифры, и только они. Поколение «финал» 05.10: --fw-number 300, SF Pro Rounded. До этого главная цифра рисовалась bold 700 — вес противоположный, и это самое заметное глазом расхождение кода с макетом
        static let light: Font.Weight = .light
        static let medium: Font.Weight = .medium
        static let regular: Font.Weight = .regular
        static let semibold: Font.Weight = .semibold
    }

    /// Межбуквенное в ТОЧКАХ, а не в em. Хендофф задаёт его в em, и перевод сделан в токенах, а не на месте вызова: `SwiftUI.tracking(_:)` принимает точки, и −0,025 в них — сотая доля точки, то есть ничего.
    enum FontTracking {
        /// Трекинг крупного заголовка. В хендоффе задан в em: `cinema.titleLarge.tracking` = −0,025em при кегле 36 → −0,9 pt. Пересчитано в точки, потому что `SwiftUI.tracking(_:)` принимает точки, а не em: оставить −0,025 значило бы дать заголовку трекинг в сотую долю точки. Решение Виктории 22.10.2026: тема «Кино» заменяет Graphite. Источник — `design_handoff_togo_ios28/tokens/togo-ios28.tokens.json`.
        static let titleLarge: CGFloat = -0.9
    }

    /// Длительности анимаций.
    enum Duration {
        /// Нажатие. Поколение «финал»: --dur-press 0.15s. Было 120ms — сопоставлено ПО РОЛИ, а не по имени: у макета длительности названы действием (press, move), у нас скоростью (instant, quick, settle), и сопоставлять их по порядку значило бы угадывать. Зовётся из TGButton:105 и DayTimeline:319 — оба про нажатие
        static let instant: Double = 0.15
        static let quick: Double = 0.18
        /// Перемещение. Поколение «финал»: --dur-move 0.3s. Было 280ms. ВНИМАНИЕ: потребителей в Swift НОЛЬ — `Token.Duration.settle` не зовётся ниоткуда, значит правка значения пока ничего не меняет на экране. Токен живой по названию и мёртвый по употреблению; это не повод его убирать (роль в системе есть), но повод не считать движение применённым
        static let settle: Double = 0.3
    }

    /// Тень в приложении одна на всё. Второй нет — так решено в макете.
    enum Elevation {
        struct Shadow: Sendable {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
        static let card = Shadow(color: Color(hex: 0x000000).opacity(0.05), radius: 10, x: 0, y: 3)
        static let float = Shadow(color: Color(hex: 0x000000).opacity(0.12), radius: 14, x: 0, y: 4)
    }

    /// Стоп градиента: доля высоты и цвет с альфой.
    /// 
    /// Маска выражена ТЕМ ЖЕ типом — чёрным с альфой, а не парой
    /// «позиция → непрозрачность». Второй тип завёл бы вторую
    /// реализацию одного правила; разбор — в описании
    /// `component.backdrop.mask`.
    struct GradientStop: Sendable, Equatable {
        let position: CGFloat
        let color: Color
    }

    /// Слой компонентов — то, что в Figma лежит свойствами внутри самого
    /// компонента. Экран сюда не лезет: он выбирает вариант.
    enum Component {
        enum ActionTile {
            static let background = Общие.night4
            static let minHeight: CGFloat = 52
            static let radius: CGFloat = 16
        }
        enum Backdrop {
            enum Height {
                static let sub: CGFloat = 360
                static let tab: CGFloat = 420
                static let today: CGFloat = 640
                static let walk: CGFloat = 520
            }
            /// Маска исчезновения фото (`backdrop.maskStops`). В хендоффе задана парами «позиция → непрозрачность» ([0.45,1],[0.92,0]); здесь те же две позиции выражены ЧЁРНЫМ С АЛЬФОЙ, а не вторым типом токена. Причина — не краткость: второй тип завёл бы вторую реализацию одного правила, а у нас записано, что третья реализация молчала в двух случаях из трёх. Чёрный с альфой и в CSS даёт дословно тот же `linear-gradient`, и в SwiftUI годится для `.mask` без перевода.
            static let mask: [GradientStop] = [
                GradientStop(position: 0.45, color: Color(hex: 0x000000FF)),
                GradientStop(position: 0.92, color: Color(hex: 0x00000000)),
            ]
            /// До пяти своих фото (`backdrop.settings.maxPhotos`).
            static let maxPhotos: Int = 5
            /// Затемнение сверху вниз (`backdrop.scrimStops`). Восемь стопов, и плато между 30 % и 38 % — не лишний стоп: это ОКНО ФОТО, самое светлое место кадра, где собаку видно. ПРЕЖНЯЯ РЕДАКЦИЯ ГОВОРИЛА «там лежит шапка» — это неверно по эталонному кадру 01 (424×896): шапка с кличкой на 9,8 %, крупный заголовок на 17 %, чип состояния на 25 %, а плато начинается на 30 % и кончается до панели показания (47 %). Все три текста стоят ВЫШЕ плато, в зоне 70→45 % затемнения, и держит их именно она. Объяснение, придуманное к верному числу, наследует его достоверность и не имеет своей: числа стопов верны и сверены с хендоффом, причина рядом с ними была подставлена. Замер 23.10.2026.
            static let scrim: [GradientStop] = [
                GradientStop(position: 0, color: Color(hex: 0x000000B3)),
                GradientStop(position: 0.14, color: Color(hex: 0x00000073)),
                GradientStop(position: 0.3, color: Color(hex: 0x00000026)),
                GradientStop(position: 0.38, color: Color(hex: 0x00000026)),
                GradientStop(position: 0.55, color: Color(hex: 0x000000BF)),
                GradientStop(position: 0.7, color: Color(hex: 0x000000F7)),
                GradientStop(position: 0.76, color: Color(hex: 0x000000FF)),
                GradientStop(position: 1, color: Color(hex: 0x000000FF)),
            ]
            enum Tint {
                static let alarm = Color(hex: 0xD5251999)
                static let dose = Color(hex: 0x1F4FFF8C)
                static let fasting = Color(hex: 0xFFC2338C)
                static let night = Color(hex: 0x14143C99)
            }
        }
        enum Banner {
            static let padding: CGFloat = 14
            static let radius: CGFloat = 24
            /// 28px в макете было мелко — плашку натощак можно было проскроллить.
            static let titleSize: CGFloat = 20
        }
        enum BottomBar {
            /// Круглая «+» → шторка «Записать».
            static let plusSize: CGFloat = 60
            static let primaryHeight: CGFloat = 60
            static let secondaryHeight: CGFloat = 60
        }
        enum Button {
            enum Destructive {
                static let background = Общие.clayBg
                static let height: CGFloat = 50
                static let label = Общие.clay
                static let radius: CGFloat = 24
            }
            enum Disabled {
                /// УСЛОВИЕ, КОТОРОЕ НАДО ПРОВЕРЯТЬ, А НЕ ПОМНИТЬ: эта роль и `semantic.surface.pressed` сидят на одном примитиве `night5`, и обязаны РАЗОЙТИСЬ в тот момент, когда у `Surface.pressed` появится первый читатель в Swift. Сегодня столкновения нет по замеру 15.10.2026: у `night5` одна производная (`Surface.pressed`) и у неё ЖИВЫХ ЧИТАТЕЛЕЙ НОЛЬ, как и у `Surface.skeleton`, `Chip.pressedBackground`, `Action.secondaryPressed` — при живом контроле `Surface.sunken` 17, `Surface.screen` 11, `Surface.card` 9. Но это «поле без читателя», а оно означает в двух случаях противоположное: появится читатель — нажатая кнопка и выключенная станут одного цвета, и обнаружится это у человека, а не у нас. Сторож на это условие стоит в `ThemeContrastTests`. Было `{semantic.surface.control}` = `night4`, то есть в светлой `#FFFFFF` — РОВНО фон экрана, байт в байт, 1,0000:1: плашки не существовало на экране, и человек видел слово «Дальше» без кнопки рядом с «Пока без собаки» того же вида. Сломано было означающее, а не контраст: подними контраст подписи на белой плашке — получишь два хорошо читаемых серых слова, между которыми по-прежнему не выбрать. Порог ≥3:1, под который эту шкалу сперва мерили, здесь не норма ничья: WCAG 1.4.11 исключает неактивные элементы, а системная рампа Apple держит выключенную заливку на 1,1–1,7:1 (systemGray4 1,52 · systemGray5 1,26). `night5` даёт 1,3909 в Light и 1,4162 в Light HC — внутри полосы Apple, и HC даёт БОЛЬШЕ, как и должен. Решение Виктории 15.10.2026, получено прямым вопросом.
                static let background = Общие.night5
                /// Было `{semantic.text.faint}` = `inkFaint`, и это НАРУШАЛО ЗАПРЕТ СВОЕГО ЖЕ ТОКЕНА: в `$description` у `inkFaint` стоит дословно «Только неактивное… Текстом и значками НЕ красится ни в каком кегле: запрет был верен и стал нужнее». А подпись кнопки и есть текст. Запрет и его нарушение жили в ОДНОМ файле, в двадцати строках друг от друга, и греп по токену находил оба — но запрет написан прозой, а нарушение значением. ПРОЗА НЕ ВЫПОЛНЯЕТСЯ. Замер 15.10.2026 по четырём режимам: `inkFaint` на новой плашке дал бы 1,80:1, то есть ХУЖЕ, чем на белом; `inkMuted` даёт Light 4,7583 · Light HC 6,4913 · Dark 5,5124 · Dark HC 6,9878 — порог 4,5 держат все четыре, и этим снимаются ВСЕ ЧЕТЫРЕ объявленных непрохождения, а не только светлые. `ink` брать нельзя: 13,59:1 прочтётся как ВКЛЮЧЁННАЯ кнопка.
                static let label = Общие.inkMuted
            }
            enum Finish {
                static let background = Общие.arcticTint
                static let height: CGFloat = 50
                static let label = Общие.ink
                static let radius: CGFloat = 24
            }
            enum Primary {
                static let background = Общие.arctic
                static let height: CGFloat = 60
                static let label = Общие.arcticInk
                static let radius: CGFloat = 999
            }
            enum Secondary {
                static let background = Общие.night4
                static let height: CGFloat = 50
                static let label = Общие.ink
                static let radius: CGFloat = 24
            }
        }
        enum Card {
            static let background = Общие.night2
            static let padding: CGFloat = 16
            static let radius: CGFloat = 24
        }
        enum CategoryBadge {
            /// Уход и занятие — один цвет, так в хендоффе.
            static let care = Color(hex: 0xC3A6FF)
            static let dose = Color(hex: 0xFF8FBF)
            /// Доза — скруглённый квадрат 12 (`category.doseShapeRadius`), а не круг. Единственный вид, у которого форма другая.
            static let doseRadius: CGFloat = 12
            static let food = Color(hex: 0xFF9A5C)
            /// `category.incident` хендоффа = `status.error`, то есть наш терракот. Своего значения у инцидента нет и заводить его не надо.
            static let incident = Общие.clay
            /// Значок внутри кружка — #111 на любой заливке.
            static let on = Color(hex: 0x111111)
            /// Значок на терракоте: #111 там, где заливка светлая, белый там, где тёмная. Разбор и числа — в описании `primitive.color.catOnIncident`.
            static let onIncident = Общие.arcticInk
            /// Тот же #A2C1FE, что ссылка.
            static let poop = Color(hex: 0xA2C1FE)
            /// Круг: 13 при 40.
            static let radius: CGFloat = 13
            /// Кружок 40 pt.
            static let size: CGFloat = 40
            static let train = Color(hex: 0xC3A6FF)
            /// Лакомство и еда — один цвет, так в хендоффе.
            static let treat = Color(hex: 0xFF9A5C)
            static let walk = Color(hex: 0x7CE0A0)
            static let water = Color(hex: 0x7FD3FF)
            static let weight = Color(hex: 0xFFD43B)
        }
        enum Chip {
            static let alarmBackground = Общие.clayBg
            static let alarmLabel = Общие.clay
            static let height: CGFloat = 44
            static let radius: CGFloat = 16
            static let restBackground = Общие.night4
            static let selectedBackground = Общие.arcticTint
        }
        enum FeedRow {
            static let background = Общие.night2
            static let minHeight: CGFloat = 60
            /// Колонка времени 44, по правому краю.
            static let timeColumn: CGFloat = 44
        }
        enum Header {
            static let buttonSize: CGFloat = 44
            /// Крупный заголовок 36.
            static let titleSize: CGFloat = 36
            /// −0,9 pt при 36.
            static let titleTracking: CGFloat = -0.9
        }
        enum ReadingPanel {
            /// «с · до» 14 semibold.
            static let captionSize: CGFloat = 14
            /// Стеклянная панель внутри, 24.
            static let glassRadius: CGFloat = 24
            static let height: CGFloat = 360
            /// При крупном кегле.
            static let heightAX: CGFloat = 220
            /// Панель целиком, 32.
            static let radius: CGFloat = 32
            /// Показание 56, SF Pro Rounded 300.
            static let readingSize: CGFloat = 56
        }
        enum ReadingTone {
            enum Alarm {
                static let chip = Color(hex: 0xD52519)
                /// Подпись на чипе тона. ВЫВЕДЕНО из цвета показания того же тона (`fg`): своих значений для подписи чипа хендофф не даёт. Кадр 02 подтверждает только час дозы — белым по индиго. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
                static let chipLabel = Общие.posterInk
                static let fg = Общие.posterInk
                static let panel = Color(hex: 0xD52519EB)
                static let primaryButton = Color(hex: 0xD52519)
            }
            enum Dose {
                static let chip = Общие.indigo
                /// Подпись на чипе тона. ВЫВЕДЕНО из цвета показания того же тона (`fg`): своих значений для подписи чипа хендофф не даёт. Кадр 02 подтверждает только час дозы — белым по индиго. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
                static let chipLabel = Общие.posterInk
                static let fg = Общие.posterInk
                static let panel = Color(hex: 0x1F4FFFEB)
                /// ЕДИНСТВЕННОЕ МЕСТО, ГДЕ ГЛАВНАЯ КНОПКА НЕ БЕЛАЯ: в час дозы она индиговая (`readingTone.dose.primaryButton` = #1F4FFF).
                static let primaryButton = Общие.indigo
            }
            enum Fasting {
                static let caption = Color(hex: 0x5A4300)
                static let chip = Color(hex: 0xFFC233)
                /// Подпись на чипе тона. ВЫВЕДЕНО из цвета показания того же тона (`fg`): своих значений для подписи чипа хендофф не даёт. Кадр 02 подтверждает только час дозы — белым по индиго. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
                static let chipLabel = Color(hex: 0x2A1D00)
                static let fg = Color(hex: 0x2A1D00)
                static let panel = Color(hex: 0xFFC233EB)
            }
            enum Night {
                static let fg = Общие.ink
                static let panel = Общие.glassStrong
                /// Фото ночью: `brightness(.7)`.
                static let photoBrightness: Double = 0.7
                /// Фото ночью: `saturate(.3)`.
                static let photoSaturation: Double = 0.3
            }
            enum Normal {
                /// Косточка: индиго, не белый акцент.
                static let bar = Общие.indigo
                /// Чип состояния «Дома» на обычном дне — БЕЛАЯ пилюля, а не стекло. В токенах хендоффа чипа у тона `normal` нет вовсе: `readingTone.normal` несёт только panel, fg и bar. Значение взято С КАДРА. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
                static let chip = Общие.arctic
                /// Подпись на белом чипе — #111111. Значение взято С КАДРА: в токенах хендоффа подписи чипа нет ни у одного тона. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
                static let chipLabel = Общие.arcticInk
                static let fg = Общие.ink
                /// Обычно — плотное стекло, а не цвет.
                static let panel = Общие.glassStrong
            }
            enum Walk {
                /// ВЫВЕДЕНО, НЕ ИЗМЕРЕНО: см. `panel`. Кнопки «Пописал» и «Стул» на этом экране СПЛОШНЫЕ (`surface.raised`), а не стеклянные — так в хендоффе.
                static let fg = Общие.ink
                /// ВЫВЕДЕНО, НЕ ИЗМЕРЕНО: своих значений у шестого тона в хендоффе нет.
                static let panel = Общие.glassStrong
            }
        }
        enum Sheet {
            static let background = Общие.night1
            static let handleColor = Общие.hairline
            static let handleHeight: CGFloat = 4
            static let handleWidth: CGFloat = 36
            static let radius: CGFloat = 36
        }
        enum TabBar {
            /// Активная вкладка — ИНДИГО, и на обычном дне тоже, где главная кнопка белая. Это и есть граница решения «индиго отменено»: отменён индиговый АКЦЕНТ ПО УМОЛЧАНИЮ (главная кнопка), а не индиго как значение. На кадре 01 белая кнопка «Просится» и синяя вкладка «Сегодня» стоят в одном кадре — читать их как одно решение нельзя. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
            static let active = Общие.indigo
            /// Таб-бар стеклянный.
            static let background = Общие.glass
            static let height: CGFloat = 64
            /// Неактивная вкладка. Замер по кадрам второго пакета 22.10.2026: `~/Downloads/design_handoff_togo_ios28 2/screenshots/01.png` (обычный день) и `02.png` (час дозы), 424×896. Прочитано глазами, не из описания.
            static let inactive = Общие.inkMuted
            static let item: CGFloat = 56
        }
        enum Timeline {
            static let alarmMark = Общие.clay
            static let gutter: CGFloat = 12
            static let nowMarker = Общие.arctic
            static let syncedMark = Color(hex: 0x5FBF9326)
        }
    }
}
