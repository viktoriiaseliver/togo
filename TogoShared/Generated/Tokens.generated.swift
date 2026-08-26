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
        static let card = Color(hex: 0xFFFFFF)
        static let hairline = Color(hex: 0xE5DDCE)
        static let screen = Color(hex: 0xFAF7F0)
        static let sunken = Color(hex: 0xF2EDE2)
    }

    /// Текст. Слабый серый допустим только с 14pt.
    enum Ink {
        static let faint = Color(hex: 0x948B7C)
        static let onAccent = Color(hex: 0x221E18)
        static let primary = Color(hex: 0x221E18)
        static let secondary = Color(hex: 0x6E6558)
        static let silhouette = Color(hex: 0x8C7B63)
    }

    /// Действия. Охряная кнопка строго одна на экран.
    enum Action {
        /// Сделала система или уже сделал человек.
        static let done = Color(hex: 0x2E7D71)
        static let doneQuiet = Color(hex: 0xE3EFEC)
        /// Строго одна охряная кнопка на экран.
        static let primary = Color(hex: 0xC87F3C)
        static let primaryQuiet = Color(hex: 0xF6E3CC)
        static let secondary = Color(hex: 0xF2EDE2)
    }

    /// Состояния: янтарь — «подожди», терракот — просрочка или кровь.
    enum Status {
        static let doneBg = Color(hex: 0xE3EFEC)
        static let doneText = Color(hex: 0x1F5A51)
        /// Пропущенная доза, кровь в стуле, удаление.
        static let overdueBg = Color(hex: 0xF7E4DC)
        static let overdueText = Color(hex: 0xA3462A)
        /// Только окно натощак: это не ошибка, а «подожди».
        static let waitingBg = Color(hex: 0xFBEFD6)
        static let waitingText = Color(hex: 0x8A5A00)
    }

    /// Отступы.
    enum Spacing {
        static let cardPadding: CGFloat = 16
        static let rowGap: CGFloat = 12
        static let screenPadding: CGFloat = 20
        static let stack: CGFloat = 14
        static let tight: CGFloat = 8
    }

    /// Радиусы.
    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 14
        static let sheet: CGFloat = 20
        /// Мелкие подложки: ячейка календаря, счётчик, бейдж.
        static let small: CGFloat = 8
        static let tile: CGFloat = 14
    }

    /// Шаг сетки. Прикладной код берёт Spacing, а не это.
    enum Space {
        static let s0: CGFloat = 0
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s2: CGFloat = 2
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let s4: CGFloat = 4
        static let s44: CGFloat = 44
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
    }

    /// Размеры контролов и иконок.
    enum Size {
        static let avatarMd: CGFloat = 40
        static let avatarSm: CGFloat = 26
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
        static let body: CGFloat = 16
        static let caption: CGFloat = 14
        static let display: CGFloat = 34
        static let hero: CGFloat = 44
        static let micro: CGFloat = 12
        static let screen: CGFloat = 28
        static let section: CGFloat = 20
        static let title: CGFloat = 17
    }

    /// Начертания.
    enum FontWeight {
        static let bold: Font.Weight = .bold
        static let medium: Font.Weight = .medium
        static let regular: Font.Weight = .regular
        static let semibold: Font.Weight = .semibold
    }

    /// Длительности анимаций.
    enum Duration {
        static let instant: Double = 0.12
        static let quick: Double = 0.18
        static let settle: Double = 0.28
    }

    /// Тень в приложении одна на всё. Второй нет — так решено в макете.
    enum Elevation {
        struct Shadow: Sendable {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
        static let card = Shadow(color: Color(hex: 0x221E18).opacity(0.05), radius: 10, x: 0, y: 3)
        static let float = Shadow(color: Color(hex: 0x221E18).opacity(0.12), radius: 14, x: 0, y: 4)
    }

    /// Слой компонентов — то, что в Figma лежит свойствами внутри самого
    /// компонента. Экран сюда не лезет: он выбирает вариант.
    enum Component {
        enum ActionTile {
            static let background = Color(hex: 0xF2EDE2)
            static let minHeight: CGFloat = 52
            static let radius: CGFloat = 14
        }
        enum Banner {
            static let padding: CGFloat = 14
            static let radius: CGFloat = 18
            /// 28px в макете было мелко — плашку натощак можно было проскроллить.
            static let titleSize: CGFloat = 20
        }
        enum Button {
            enum Destructive {
                static let background = Color(hex: 0xF7E4DC)
                static let height: CGFloat = 50
                static let label = Color(hex: 0xA3462A)
                static let radius: CGFloat = 14
            }
            enum Disabled {
                static let background = Color(hex: 0xF2EDE2)
                static let label = Color(hex: 0x948B7C)
            }
            enum Finish {
                static let background = Color(hex: 0xE3EFEC)
                static let height: CGFloat = 50
                static let label = Color(hex: 0x1F5A51)
                static let radius: CGFloat = 14
            }
            enum Hold {
                static let background = Color(hex: 0xFBEFD6)
                static let height: CGFloat = 50
                static let label = Color(hex: 0x8A5A00)
                static let radius: CGFloat = 14
            }
            enum Primary {
                static let background = Color(hex: 0xC87F3C)
                static let height: CGFloat = 52
                static let label = Color(hex: 0x221E18)
                static let radius: CGFloat = 14
            }
            enum Secondary {
                static let background = Color(hex: 0xF2EDE2)
                static let height: CGFloat = 50
                static let label = Color(hex: 0x221E18)
                static let radius: CGFloat = 14
            }
        }
        enum Card {
            static let background = Color(hex: 0xFFFFFF)
            static let padding: CGFloat = 16
            static let radius: CGFloat = 18
        }
        enum Chip {
            static let alarmBackground = Color(hex: 0xF7E4DC)
            static let alarmLabel = Color(hex: 0xA3462A)
            static let height: CGFloat = 44
            static let radius: CGFloat = 14
            static let restBackground = Color(hex: 0xF2EDE2)
            static let selectedBackground = Color(hex: 0xF6E3CC)
        }
        enum Sheet {
            static let background = Color(hex: 0xFAF7F0)
            static let handleColor = Color(hex: 0xE5DDCE)
            static let handleHeight: CGFloat = 4
            static let handleWidth: CGFloat = 36
            static let radius: CGFloat = 20
        }
        enum Timeline {
            static let alarmMark = Color(hex: 0xA3462A)
            static let gutter: CGFloat = 12
            static let nowMarker = Color(hex: 0xC87F3C)
            static let syncedMark = Color(hex: 0x2E7D71)
        }
    }
}
