// Сгенерировано Tools/generate_tokens.py из DesignTokens/tokens.json.
// Не редактировать руками: правки перезапишет `make tokens`.
//
// Источник правды — tokens.json. Тот же файл импортируется в Figma
// как коллекции переменных, поэтому имена здесь и имена в Figma совпадают.

import SwiftUI

/// Токены Того. Экраны читают Semantic и Component; Primitive — только
/// внутри дизайн-системы.
nonisolated enum Token {

    /// Поверхности: бумага, карточка, утопленное, хайрлайн.
    enum Surface {
        static let card = Color(Dyn(dark: 0x181818, light: 0xECEDF0, darkHC: 0x181818, lightHC: 0xECEDF0))
        static let control = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
        /// Стекло таббара и круглых кнопок
        static let glass = Color(Dyn(dark: 0x343434B8, light: 0xFFFFFFD1, darkHC: 0x343434B8, lightHC: 0xFFFFFFD1))
        /// Внутренний край стекла
        static let glassEdge = Color(hex: 0xFFFFFF1A)
        static let hairline = Color(Dyn(dark: 0x3A3A3A, light: 0xD6D9DD, darkHC: 0x3A3A3A, lightHC: 0x7D8085))
        static let pressed = Color(Dyn(dark: 0x383838, light: 0xD7DBE0, darkHC: 0x383838, lightHC: 0xD6D9DD))
        static let screen = Color(Dyn(dark: 0x050503, light: 0xFFFFFF, darkHC: 0x050503, lightHC: 0xFFFFFF))
        /// Затемнение под шторкой
        static let scrim = Color(Dyn(dark: 0x0000008C, light: 0x10111252, darkHC: 0x0000008C, lightHC: 0x10111252))
        static let sunken = Color(Dyn(dark: 0x1F1F1F, light: 0xE3E5E8, darkHC: 0x1F1F1F, lightHC: 0xE3E5E8))
    }

    /// Текст. `faint` — 2,5:1, текстом и значками НЕ красится ни в каком кегле: разрешение «только с 14pt» было неверным и развело его по двадцати четырём файлам.
    enum Ink {
        static let faint = Color(Dyn(dark: 0x6D6D6D, light: 0xA1A4A8, darkHC: 0x8A8A86, lightHC: 0x7D8085))
        static let onAccent = Color(Dyn(dark: 0x0B0D2E, light: 0xFFFFFF, darkHC: 0x0B0D2E, lightHC: 0xFFFFFF))
        static let primary = Color(Dyn(dark: 0xF4F4F2, light: 0x101112, darkHC: 0xF4F4F2, lightHC: 0x101112))
        static let secondary = Color(Dyn(dark: 0xB2B2AE, light: 0x5A5D61, darkHC: 0xC8C8C4, lightHC: 0x45484C))
        static let silhouette = Color(Dyn(dark: 0xB2B2AE, light: 0x5A5D61, darkHC: 0xC8C8C4, lightHC: 0x45484C))
    }

    /// Действия. Охряная кнопка строго одна на экран.
    enum Action {
        static let done = Color(hex: 0x5FBF9326)
        static let doneQuiet = Color(hex: 0x5FBF9326)
        /// «Сделано» СЛОВАМИ. Отдельный токен, потому что done — это тинт 15 %: как чернила он даёт 1,31:1 на карточке, вдвое хуже уже запрещённого faint. Та же пара, что waitingText и overdueText.
        static let doneText = Color(hex: 0x7FD3A8)
        static let primary = Color(Dyn(dark: 0xA2C1FE, light: 0x0E14A1, darkHC: 0xA2C1FE, lightHC: 0x0E14A1))
        /// Нажатое главное действие
        static let primaryPressed = Color(Dyn(dark: 0x7BA5FE, light: 0x080679, darkHC: 0x7BA5FE, lightHC: 0x080679))
        static let primaryQuiet = Color(Dyn(dark: 0xA2C1FE2E, light: 0x0E14A138, darkHC: 0xA2C1FE2E, lightHC: 0x0E14A138))
        static let secondary = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
    }

    /// Состояния: янтарь — «подожди», терракот — просрочка или кровь.
    enum Status {
        static let doneBg = Color(hex: 0x5FBF9326)
        static let doneText = Color(Dyn(dark: 0xF4F4F2, light: 0x101112, darkHC: 0xF4F4F2, lightHC: 0x101112))
        static let overdueBg = Color(Dyn(dark: 0x4D1F22, light: 0xF7D5CF, darkHC: 0x4D1F22, lightHC: 0xF7D5CF))
        static let overdueText = Color(Dyn(dark: 0xFF7A66, light: 0xAE2219, darkHC: 0xFFA696, lightHC: 0x9B100E))
        /// Запас кончается — плашка. ≤ 7 дней; ≤ 3 берёт overdue
        static let stockLowBg = Color(Dyn(dark: 0x4A2A10, light: 0xFFEBD9, darkHC: 0x4A2A10, lightHC: 0xFFEBD9))
        /// Запас кончается — текст и значок. Заведён 05.10 вечером вторым шагом: примитив положили в tokens.json, а семантического имени не дали — и в Tokens.generated.swift его не оказалось ВОВСЕ. Генератор поднимает в Swift то, на что ссылается семантика; примитив без алиаса до слоя вида не доезжает. Нашёл togo-9e, искавший, чем покрасить уровень .low. ПРАВКА 07.10 вечер, togo-1e: у лестницы запаса ЧЕТЫРЕ ступени (PillSupplyAdvisor.Level: ok · low · urgent · out), а статусных цветов три. Ступень .out («кончилось») красится ТЕМ ЖЕ терракотом, что .urgent, и это решение, а не недосмотр: четвёртого статусного цвета у системы нет, и заводить его ради одной ступени нельзя — различать «пора покупать» и «уже нечего дать» обязано СЛОВО. У нас записано, что срочность не передаётся одним цветом; здесь то же правило с другой стороны — раз цвет не различает, различает текст. Заведёшь пятый цвет под .out — сначала проверь, что слова не хватило.
        static let stockLowText = Color(Dyn(dark: 0xFFA15C, light: 0xB85400, darkHC: 0xFFA15C, lightHC: 0xB85400))
        static let waitingBg = Color(Dyn(dark: 0x4A300A, light: 0xFCEBCB, darkHC: 0x4A300A, lightHC: 0xFCEBCB))
        static let waitingText = Color(Dyn(dark: 0xF7C75F, light: 0x8A640F, darkHC: 0xF7C75F, lightHC: 0x6B4C0C))
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
        static let card: CGFloat = 28
        static let control: CGFloat = 24
        /// Радиус нижних углов плаката. Макет: border-radius: 0 0 44px 44px.
        static let poster: CGFloat = 44
        static let sheet: CGFloat = 36
        static let small: CGFloat = 12
        static let tile: CGFloat = 16
    }

    /// Плакат — верхняя треть «Сегодня» и «На улице». Цвет блока = РЕЖИМ ДНЯ, и правило выбора в `TogoShared/Domain/PosterMode.swift`, не во вью: его спрашивают экран, виджет и «остров». Шторки плаката не несут.
    enum Poster {
        static let background = Color(Dyn(dark: 0x2A3670, light: 0x3F5BC4, darkHC: 0x2A3670, lightHC: 0x3F5BC4))
        static let backgroundAlarm = Color(Dyn(dark: 0x5E2A22, light: 0xB5402F, darkHC: 0x5E2A22, lightHC: 0xB5402F))
        static let backgroundDose = Color(Dyn(dark: 0xA2C1FE, light: 0x0E14A1, darkHC: 0xA2C1FE, lightHC: 0x0E14A1))
        static let backgroundFasting = Color(Dyn(dark: 0x4A3A14, light: 0x8A640F, darkHC: 0x4A3A14, lightHC: 0x8A640F))
        static let backgroundQuiet = Color(Dyn(dark: 0x181818, light: 0xECEDF0, darkHC: 0x181818, lightHC: 0xECEDF0))
        static let bar = Color(Dyn(dark: 0xA2C1FE, light: 0x0E14A1, darkHC: 0xA2C1FE, lightHC: 0x0E14A1))
        static let barOnDose = Color(Dyn(dark: 0x0B0D2E, light: 0xFFFFFF, darkHC: 0x0B0D2E, lightHC: 0xFFFFFF))
        /// ТОЛЬКО НЕЙТРАЛЬНЫЙ БЛОК. На цветных — captionOnColor, на дозе — captionOnDose. В светлой на синем блоке даёт 1,10.
        static let caption = Color(Dyn(dark: 0xB2B2AE, light: 0x5A5D61, darkHC: 0xC8C8C4, lightHC: 0x45484C))
        /// Подпись плаката на ЦВЕТНОМ блоке.
        static let captionOnColor = Color(Dyn(dark: 0xB2B2AE, light: 0xFFFFFFE0, darkHC: 0xB2B2AE, lightHC: 0xFFFFFFE0))
        /// Подпись плаката на заливке дозы. Отдельная от caption потому, что доза — единственный режим дня со СВЕТЛОЙ подложкой: остальные четыре кладут текст на тёмный блок, и там caption честен. У плаката ПАКЕТА режима дозы нет вовсе — его bg всегда тёмный блок с белым текстом, — то есть инверсия наша, и цена её в том, что для неё нужен свой тихий цвет.
        static let captionOnDose = Color(Dyn(dark: 0x2E3866, light: 0xD9E3FC, darkHC: 0x2E3866, lightHC: 0xD9E3FC))
        /// ТОЛЬКО НЕЙТРАЛЬНЫЙ БЛОК (backgroundQuiet). На цветных блоках берётся labelOnColor, на дозе labelOnDose: у плаката ТРИ семьи текста, а не одна. Замер 07.10.2026: этот токен на синем блоке в светлой даёт 3,15 — он честен только там, где подложка нейтральна.
        static let label = Color(Dyn(dark: 0xF4F4F2, light: 0x101112, darkHC: 0xF4F4F2, lightHC: 0x101112))
        /// Заголовок плаката на ЦВЕТНОМ блоке: обычный, тревожный, натощак.
        static let labelOnColor = Color(Dyn(dark: 0xF4F4F2, light: 0xFFFFFF, darkHC: 0xF4F4F2, lightHC: 0xFFFFFF))
        static let labelOnDose = Color(Dyn(dark: 0x0B0D2E, light: 0xFFFFFF, darkHC: 0x0B0D2E, lightHC: 0xFFFFFF))
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
        /// Высота косточки прогресса на плакате. Макет: height 16px. ПАРЫ В ПАКЕТЕ НЕТ: среди size/ шестнадцати нет вовсе, а space/16, radius/inner и type/size/callout равны шестнадцати СЛУЧАЙНО — по роли они косточке не родня. Взять любое из них значило бы завести связь, которой нет, и в день, когда иконки станут 18, косточка поехала бы за ними без причины.
        static let bone: CGFloat = 16
        /// Главное действие — капсула 60 pt. Только оно
        static let capsule: CGFloat = 60
        /// Плитка действия. Было общим с главной кнопкой: один номер держал две роли, и «капсула 60 pt» из «Льда» растила заодно плитки
        static let controlL: CGFloat = 52
        static let controlM: CGFloat = 50
        static let controlXL: CGFloat = 54
        static let hairline: CGFloat = 1
        static let handleH: CGFloat = 4
        static let handleW: CGFloat = 36
        static let iconLg: CGFloat = 20
        static let iconMd: CGFloat = 16
        static let iconSm: CGFloat = 13
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
        /// Было 12. Ниже четырнадцати в системе не существует
        static let micro: CGFloat = 14
        /// Название экрана
        static let screen: CGFloat = 34
        /// Заголовок карточки
        static let section: CGFloat = 20
        static let title: CGFloat = 17
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

    /// Слой компонентов — то, что в Figma лежит свойствами внутри самого
    /// компонента. Экран сюда не лезет: он выбирает вариант.
    enum Component {
        enum ActionTile {
            static let background = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
            static let minHeight: CGFloat = 52
            static let radius: CGFloat = 16
        }
        enum Banner {
            static let padding: CGFloat = 14
            static let radius: CGFloat = 28
            /// 28px в макете было мелко — плашку натощак можно было проскроллить.
            static let titleSize: CGFloat = 20
        }
        enum Button {
            enum Destructive {
                static let background = Color(Dyn(dark: 0x4D1F22, light: 0xF7D5CF, darkHC: 0x4D1F22, lightHC: 0xF7D5CF))
                static let height: CGFloat = 50
                static let label = Color(Dyn(dark: 0xFF7A66, light: 0xAE2219, darkHC: 0xFFA696, lightHC: 0x9B100E))
                static let radius: CGFloat = 24
            }
            enum Disabled {
                static let background = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
                static let label = Color(Dyn(dark: 0x6D6D6D, light: 0xA1A4A8, darkHC: 0x8A8A86, lightHC: 0x7D8085))
            }
            enum Finish {
                static let background = Color(Dyn(dark: 0xA2C1FE2E, light: 0x0E14A138, darkHC: 0xA2C1FE2E, lightHC: 0x0E14A138))
                static let height: CGFloat = 50
                static let label = Color(Dyn(dark: 0xF4F4F2, light: 0x101112, darkHC: 0xF4F4F2, lightHC: 0x101112))
                static let radius: CGFloat = 24
            }
            enum Primary {
                static let background = Color(Dyn(dark: 0xA2C1FE, light: 0x0E14A1, darkHC: 0xA2C1FE, lightHC: 0x0E14A1))
                static let height: CGFloat = 60
                static let label = Color(Dyn(dark: 0x0B0D2E, light: 0xFFFFFF, darkHC: 0x0B0D2E, lightHC: 0xFFFFFF))
                static let radius: CGFloat = 999
            }
            enum Secondary {
                static let background = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
                static let height: CGFloat = 50
                static let label = Color(Dyn(dark: 0xF4F4F2, light: 0x101112, darkHC: 0xF4F4F2, lightHC: 0x101112))
                static let radius: CGFloat = 24
            }
        }
        enum Card {
            static let background = Color(Dyn(dark: 0x181818, light: 0xECEDF0, darkHC: 0x181818, lightHC: 0xECEDF0))
            static let padding: CGFloat = 16
            static let radius: CGFloat = 28
        }
        enum Chip {
            static let alarmBackground = Color(Dyn(dark: 0x4D1F22, light: 0xF7D5CF, darkHC: 0x4D1F22, lightHC: 0xF7D5CF))
            static let alarmLabel = Color(Dyn(dark: 0xFF7A66, light: 0xAE2219, darkHC: 0xFFA696, lightHC: 0x9B100E))
            static let height: CGFloat = 44
            static let radius: CGFloat = 16
            static let restBackground = Color(Dyn(dark: 0x2C2C2C, light: 0xFFFFFF, darkHC: 0x2C2C2C, lightHC: 0xFFFFFF))
            static let selectedBackground = Color(Dyn(dark: 0xA2C1FE2E, light: 0x0E14A138, darkHC: 0xA2C1FE2E, lightHC: 0x0E14A138))
        }
        enum Sheet {
            static let background = Color(Dyn(dark: 0x050503, light: 0xFFFFFF, darkHC: 0x050503, lightHC: 0xFFFFFF))
            static let handleColor = Color(Dyn(dark: 0x3A3A3A, light: 0xD6D9DD, darkHC: 0x3A3A3A, lightHC: 0x7D8085))
            static let handleHeight: CGFloat = 4
            static let handleWidth: CGFloat = 36
            static let radius: CGFloat = 36
        }
        enum Timeline {
            static let alarmMark = Color(Dyn(dark: 0xFF7A66, light: 0xAE2219, darkHC: 0xFFA696, lightHC: 0x9B100E))
            static let gutter: CGFloat = 12
            static let nowMarker = Color(Dyn(dark: 0xA2C1FE, light: 0x0E14A1, darkHC: 0xA2C1FE, lightHC: 0x0E14A1))
            static let syncedMark = Color(hex: 0x5FBF9326)
        }
    }
}
