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
        static let card = Color(hex: 0x181818)
        static let control = Color(hex: 0x2C2C2C)
        /// Стекло таббара и круглых кнопок
        static let glass = Color(hex: 0x343434B8)
        /// Внутренний край стекла
        static let glassEdge = Color(hex: 0xFFFFFF1A)
        static let hairline = Color(hex: 0x3A3A3A)
        static let pressed = Color(hex: 0x383838)
        static let screen = Color(hex: 0x050503)
        /// Затемнение под шторкой
        static let scrim = Color(hex: 0x0000008C)
        static let sunken = Color(hex: 0x1F1F1F)
    }

    /// Текст. `faint` — 2,5:1, текстом и значками НЕ красится ни в каком кегле: разрешение «только с 14pt» было неверным и развело его по двадцати четырём файлам.
    enum Ink {
        static let faint = Color(hex: 0x6D6D6D)
        static let onAccent = Color(hex: 0x111111)
        static let primary = Color(hex: 0xF4F4F2)
        static let secondary = Color(hex: 0xB2B2AE)
        static let silhouette = Color(hex: 0xB2B2AE)
    }

    /// Действия. Охряная кнопка строго одна на экран.
    enum Action {
        static let done = Color(hex: 0x5FBF9326)
        static let doneQuiet = Color(hex: 0x5FBF9326)
        /// «Сделано» СЛОВАМИ. Отдельный токен, потому что done — это тинт 15 %: как чернила он даёт 1,31:1 на карточке, вдвое хуже уже запрещённого faint. Та же пара, что waitingText и overdueText.
        static let doneText = Color(hex: 0x7FD3A8)
        static let primary = Color(hex: 0xD4F75F)
        /// Нажатое главное действие
        static let primaryPressed = Color(hex: 0xC1E348)
        static let primaryQuiet = Color(hex: 0xD4F75F2E)
        static let secondary = Color(hex: 0x2C2C2C)
    }

    /// Состояния: янтарь — «подожди», терракот — просрочка или кровь.
    enum Status {
        static let doneBg = Color(hex: 0x5FBF9326)
        static let doneText = Color(hex: 0xF4F4F2)
        static let overdueBg = Color(hex: 0x4D1F22)
        static let overdueText = Color(hex: 0xFF7A66)
        /// Запас кончается — плашка. ≤ 7 дней; ≤ 3 берёт overdue
        static let stockLowBg = Color(hex: 0x4A2A10)
        /// Запас кончается — текст и значок. Заведён 05.10 вечером вторым шагом: примитив положили в tokens.json, а семантического имени не дали — и в Tokens.generated.swift его не оказалось ВОВСЕ. Генератор поднимает в Swift то, на что ссылается семантика; примитив без алиаса до слоя вида не доезжает. Нашёл togo-9e, искавший, чем покрасить уровень .low
        static let stockLowText = Color(hex: 0xFFA15C)
        static let waitingBg = Color(hex: 0x4A300A)
        static let waitingText = Color(hex: 0xF7C75F)
    }

    /// Отступы.
    enum Spacing {
        static let cardPadding: CGFloat = 16
        static let screenPadding: CGFloat = 18
        static let stack: CGFloat = 12
    }

    /// Радиусы.
    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 16
        static let sheet: CGFloat = 40
        static let small: CGFloat = 12
        static let tile: CGFloat = 18
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
            static let background = Color(hex: 0x2C2C2C)
            static let minHeight: CGFloat = 52
            static let radius: CGFloat = 18
        }
        enum Banner {
            static let padding: CGFloat = 14
            static let radius: CGFloat = 20
            /// 28px в макете было мелко — плашку натощак можно было проскроллить.
            static let titleSize: CGFloat = 20
        }
        enum Button {
            enum Destructive {
                static let background = Color(hex: 0x4D1F22)
                static let height: CGFloat = 50
                static let label = Color(hex: 0xFF7A66)
                static let radius: CGFloat = 16
            }
            enum Disabled {
                static let background = Color(hex: 0x2C2C2C)
                static let label = Color(hex: 0x6D6D6D)
            }
            enum Finish {
                static let background = Color(hex: 0xD4F75F2E)
                static let height: CGFloat = 50
                static let label = Color(hex: 0xF4F4F2)
                static let radius: CGFloat = 16
            }
            enum Primary {
                static let background = Color(hex: 0xD4F75F)
                static let height: CGFloat = 60
                static let label = Color(hex: 0x111111)
                static let radius: CGFloat = 30
            }
            enum Secondary {
                static let background = Color(hex: 0x2C2C2C)
                static let height: CGFloat = 50
                static let label = Color(hex: 0xF4F4F2)
                static let radius: CGFloat = 16
            }
        }
        enum Card {
            static let background = Color(hex: 0x181818)
            static let padding: CGFloat = 16
            static let radius: CGFloat = 20
        }
        enum Chip {
            static let alarmBackground = Color(hex: 0x4D1F22)
            static let alarmLabel = Color(hex: 0xFF7A66)
            static let height: CGFloat = 44
            static let radius: CGFloat = 18
            static let restBackground = Color(hex: 0x2C2C2C)
            static let selectedBackground = Color(hex: 0xD4F75F2E)
        }
        enum Sheet {
            static let background = Color(hex: 0x050503)
            static let handleColor = Color(hex: 0x3A3A3A)
            static let handleHeight: CGFloat = 4
            static let handleWidth: CGFloat = 36
            static let radius: CGFloat = 40
        }
        enum Timeline {
            static let alarmMark = Color(hex: 0xFF7A66)
            static let gutter: CGFloat = 12
            static let nowMarker = Color(hex: 0xD4F75F)
            static let syncedMark = Color(hex: 0x5FBF9326)
        }
    }
}
