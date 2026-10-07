import SwiftUI
import AppIntents

/// Вид живой активности «выход идёт» — вынесен из `TogoWidgets` 07.10.2026.
///
/// **Зачем переезд, и это не аккуратность.** До него карточка «острова»
/// принимала `ActivityViewContext<WalkActivityAttributes>`, а его **вне
/// живой активности не построить ничем** — ни тестом, ни превью,
/// ни галереей. То есть поверхность, которую человек видит, когда
/// телефон лежит в кармане на улице, была единственной в продукте,
/// которую нельзя принять кадром: ни подписей, ни кнопок, ни контраста
/// на ней не проверял глазами никто, потому что было нечем.
///
/// > **Поверхность без кадра — это не «непроверенная», а
/// > «непроверяемая».** Первое лечится взглядом, второе только
/// > переделкой входа.
///
/// Цена такой поверхности у нас уже оплачена, на соседнем проекте:
/// у Timer карточка Live Activity была ровно в этом положении,
/// и отзыв «проблемы с виджетом» жил незамеченным не потому, что плохо
/// смотрели, а потому что смотреть было не на что. Приём тот же, каким
/// 05.10 вынесли вид виджета (`TogoShared/Widgets/TodayWidgetView`),
/// и он окупился в тот же день: галерея дважды показала не ту ступень,
/// чего сборка не показывала.
///
/// **Вид не знает ни про `ActivityKit`, ни про контекст.** Он принимает
/// четыре обычных значения, и это нарочно: пока в нём оставалась хоть
/// одна строка, читающая среду, его нельзя было построить в галерее —
/// вернулась бы и непроверяемость. Расширение превращает контекст
/// в значения и больше не делает ничего; `WalkLiveActivity` после
/// переезда — обёртка без логики.
///
/// **Чего этот переезд НЕ доказывает.** Что человек увидит на «острове»
/// именно это. Форму «острова» рисует система, ширины принадлежат ей,
/// и галерея отвечает на вопрос «что написано и как свёрстано», а не
/// «влезет ли». Разница та же, что у лестницы ширин в галерее виджета.
public struct WalkActivityView: View {
    public let dogName: String
    public let startedBy: String
    public let startedAt: Date
    public let tally: String?

    public init(dogName: String, startedBy: String, startedAt: Date, tally: String?) {
        self.dogName = dogName
        self.startedBy = startedBy
        self.startedAt = startedAt
        self.tally = tally
    }

    /// Подпись под таймером: что успели отметить, иначе — кто вывел.
    ///
    /// Своя защита нужна потому, что вид принимает значение от кого
    /// угодно: место вызова (`LiveActivityController`) кличку уже
    /// защищает, но функция обязана держаться сама — ровно так защищены
    /// `SnapshotText.inlineText` и текст уведомления натощак. Без неё
    /// при пустой кличке строка читалась бы «Виктория вывела »,
    /// с висящим пробелом вместо имени.
    ///
    /// **Откат падежный, и это не придирка — это кадр 07.10.2026.**
    /// Первая редакция ставила сюда `Fmt.dogNameOrFallback`, то есть
    /// именительное «Собака», и галерея показала «Виктория вывела
    /// **Собака**». Висящий пробел я убрала и завела неграмотность:
    /// слот здесь винительный, а запасное слово написано для слотов
    /// именительных — заголовка профиля и подписи вкладки.
    ///
    /// Поэтому `Fmt.dogName` (он отдаёт `nil` на пустой) плюс откат
    /// в нужном падеже на месте вызова. Это не новое слово в продукт,
    /// а то самое устройство, ради которого `nameIfAny` и заведена:
    /// падежный откат пишется там, где известен падеж.
    ///
    /// > **Кадр поймал то, чего не видел ни один сторож:** строка
    /// > непустая, кличка подставлена, разделитель на месте —
    /// > и по-русски так не говорят.
    /// **Откат идёт через каталог — правка 07.10.2026, `togo-08`.**
    /// Падеж остался на месте вызова, а слово перестало быть литералом:
    /// `"собаку"` в каталог не шло вовсе, и француз с украинцем видели
    /// русское слово в «острове». Ключа «собаку» в каталоге не было —
    /// есть только именительное «Собака», поэтому `dogNameOrFallback`
    /// здесь по-прежнему не годится.
    ///
    /// `fr` и `uk` у нового ключа **объявлены пробелом намеренно**:
    /// винительную форму выбирает переводчица, список всех пяти строк
    /// «острова» — в `docs/journal/2026-10-07.md`. Пробел виден сторожу
    /// охвата и потому имеет хозяина; литерал не видел никто.
    public var подпись: String {
        tally ?? "\(startedBy) вывела \(Fmt.dogName(dogName) ?? String(localized: "собаку"))"
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("выход идёт")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Token.Action.primary)
                Text(startedAt, style: .timer)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Token.Ink.primary)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            WalkMarkButtons()
        }
        .padding(14)
    }
}

/// Развёрнутый «остров»: три области, каждая своим видом.
///
/// Разделены потому, что `DynamicIslandExpandedRegion` принимает
/// содержимое по одной области и собрать их в один вид нельзя —
/// а значит кадром надо брать каждую отдельно, иначе «сняли остров»
/// будет значить «сняли одну треть».
public enum WalkIslandView {

    public struct Leading: View {
        public let dogName: String
        public init(dogName: String) { self.dogName = dogName }
        public var body: some View {
            Label(Fmt.dogNameOrFallback(dogName), systemImage: "figure.walk")
                .font(.caption)
        }
    }

    public struct Trailing: View {
        public let startedAt: Date
        public init(startedAt: Date) { self.startedAt = startedAt }
        public var body: some View {
            Text(startedAt, style: .timer)
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .frame(maxWidth: 64)
        }
    }

    public struct Bottom: View {
        public let startedBy: String
        public let dogName: String
        public let tally: String?
        public init(startedBy: String, dogName: String, tally: String?) {
            self.startedBy = startedBy
            self.dogName = dogName
            self.tally = tally
        }

        /// Здесь подпись короче, чем на локскране: места меньше.
        /// Откат тот же и падеж тот же — винительный, «вывел кого»,
        /// и через каталог тем же ключом, что на локскране (07.10.2026).
        public var подпись: String {
            tally ?? "вывел \(Fmt.dogName(dogName) ?? String(localized: "собаку"))"
        }

        public var body: some View {
            VStack(spacing: 6) {
                Text(подпись)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                WalkMarkButtons()
            }
        }
    }
}

/// Две кнопки, обе крупные.
///
/// Список короткий намеренно: на морозе одной рукой человек попадёт
/// в две большие цели, а не в восемь маленьких. Всё остальное —
/// в приложении, куда он всё равно заглянет, когда вернётся.
public struct WalkMarkButtons: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            кнопка(.urine)
            кнопка(.stool)
        }
    }

    private func кнопка(_ kind: WalkMarkKind) -> some View {
        Button(intent: WalkMarkIntent(kind)) {
            VStack(spacing: 2) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(kind.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 56, height: 48)
        }
        .buttonStyle(.plain)
        .tint(Token.Action.primary)
        .accessibilityLabel("Отметить: \(kind.title)")
    }
}
