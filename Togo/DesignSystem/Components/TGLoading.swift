import SwiftUI

/// Figma: `Loading`. Состояние ожидания.
///
/// Молчащий экран во время работы читается как сломанный. Спиннер без слов
/// читается почти так же: непонятно, чего ждать и сколько. Поэтому здесь
/// всегда есть строка, которая говорит, что именно происходит.
struct TGLoading: View {
    let message: LocalizedStringKey
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            ProgressView()
                .tint(Token.Ink.secondary)
            Text(message)
                .textStyle(AppFont.caption)
                .wraps()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isCompact ? Token.Size.tapTarget : 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}

/// Пустое состояние одного вида на всё приложение: что это, почему пусто
/// и что нажать. «Нет данных» без объяснения — это тупик.
///
/// **Вход — предмет, а не картинка.** Раньше каждый экран писал имя
/// SF Symbol строкой, и таких мест было двенадцать. Иллюстрации пакета
/// дизайна окт 2026 легли бы рядом тринадцатой строкой, а вместе
/// с ними — вторая таблица соответствия: кто какую сцену рисует.
/// Две таблицы одного правила расходятся молча, и у Togo это записано
/// трижды.
///
/// Поэтому экран называет **то, про что он пуст** — то есть себя,
/// чего он не может не знать, — а чем это нарисовать, решает
/// `Subject.look` ниже, в одном месте.
///
/// **Почему предмет, а не `UsageLog.Screen`.** Экран у нас уже есть,
/// и ключом он напрашивается — но у пейвола пустое состояние про
/// **офлайн**, а не про Pro: «цены не загрузились». По ключу-экрану
/// пейвол получил бы сцену `paywall`, то есть рисунок про подписку
/// над сообщением про связь. Пустое состояние — не свойство экрана,
/// а свойство того, чего на нём нет.
struct EmptyStateCard: View {

    /// Про что пусто. Закрытый список: новое пустое состояние —
    /// это решение, а не строка на месте вызова.
    enum Subject: String, CaseIterable {
        case day             // лента дня
        case feeding         // кормления
        case foodStock       // запас корма
        case history         // история
        case family          // общий дневник
        case care            // уход
        case heat            // течки
        case health          // препараты и схемы
        case training        // занятия
        case trainingLibrary // библиотека упражнений
        case dog             // собаки ещё нет
        case offline         // не загрузилось из сети
    }

    /// Чем рисуется предмет. Единственная таблица соответствия
    /// в приложении.
    ///
    /// Иллюстрация стоит там, **где её назвал дизайн**, и только там.
    /// Остальные предметы держат SF Symbol — это не недоделка, а отказ
    /// угадывать: из восьми сцен пакета три (`treat`, `onboarding`,
    /// `paywall`) адреса в пустых состояниях не имеют, и назначить их
    /// на глаз значило бы завести ту самую вторую таблицу, только
    /// в голове.
    enum Look {
        case illustration(TGIllustration.Scene)
        case symbol(String)
    }

    let subject: Subject
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        TGCard {
            switch subject.look {
            case .illustration(let scene):
                // Высота меньше паспортных 160: карточка пустого
                // состояния несёт ещё заголовок, текст и кнопку,
                // и на узком экране рисунок в полный рост выдавливал
                // кнопку за сгиб.
                TGIllustration(scene: scene, height: 112)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Token.Ink.silhouette)
                    .accessibilityHidden(true)
            }
            Text(title).textStyle(AppFont.cardTitle)
            Text(message).textStyle(AppFont.caption)
            if let actionTitle, let action {
                TGButton(title: actionTitle, variant: .secondary, size: .medium, action: action)
            }
        }
    }
}

extension EmptyStateCard.Subject {

    /// Единственное место, где предмет превращается в рисунок.
    ///
    /// Адреса, названные планом дизайна прямо: «пустая история —
    /// иллюстрация `history`», «пустой запас — `stock`», «офлайн —
    /// `offline`». Ещё два взяты не с глаз, а по собственному
    /// определению сцены в `TGIllustration.Scene`: `feed // кормление`
    /// и `family // общий дневник` — других экранов с этим предметом
    /// в приложении нет.
    var look: EmptyStateCard.Look {
        switch self {
        case .history: .illustration(.history)
        case .foodStock: .illustration(.stock)
        case .offline: .illustration(.offline)
        case .feeding: .illustration(.feed)
        case .family: .illustration(.family)

        // Сцены под эти предметы в пакете нет. Символ — не заглушка
        // «пока нет иллюстрации», а текущее решение: появится сцена —
        // появится строка здесь, и ровно одна.
        case .day: .symbol("pawprint")
        case .care: .symbol("scissors")
        case .heat: .symbol("calendar.badge.clock")
        case .health: .symbol("pills")
        case .training: .symbol("hand.raised")
        case .trainingLibrary: .symbol("target")
        case .dog: .symbol("pawprint")
        }
    }
}

/// Три состояния одного экрана: ждём, пусто, есть что показать.
///
/// Вынесено в один компонент, потому что раньше каждый экран решал это
/// по-своему, и «загружается» не было вообще ни на одном.
struct TGStateful<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    var loadingMessage: LocalizedStringKey
    /// Про что пусто. Не имя картинки: чем рисовать — решает
    /// `EmptyStateCard.Subject.look`, и это единственное место.
    var emptySubject: EmptyStateCard.Subject
    var emptyTitle: LocalizedStringKey
    var emptyMessage: LocalizedStringKey
    var emptyActionTitle: LocalizedStringKey?
    var emptyAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        if isLoading {
            TGCard { TGLoading(message: loadingMessage) }
                .transition(.opacity)
        } else if isEmpty {
            EmptyStateCard(
                subject: emptySubject,
                title: emptyTitle,
                message: emptyMessage,
                actionTitle: emptyActionTitle,
                action: emptyAction
            )
            .transition(.opacity)
        } else {
            content
        }
    }
}
