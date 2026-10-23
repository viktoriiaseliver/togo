import SwiftUI

/// Кружок категории в ленте дня — **одно место на всё приложение**.
///
/// Рекомендация хендоффа 22.10.2026, раздел «Рекомендации» 3: «Кружок
/// категории — один `CategoryBadge(type:)`, а не девять мест». До этой
/// правки вид записи превращался в оформление в трёх местах сразу:
/// `DomainStyle.titleColor` красил заголовок, `DayTimeline.marker` рисовал
/// кружок 24 pt своим `ZStack`, а каждая шторка ставила значок сама.
///
/// Геометрия — из хендоффа, раздел «Лента дня»: кружок 40, значок по
/// центру; **у дозы — скруглённый квадрат радиусом 12, а не круг**.
/// Форма здесь несёт смысл, а не вкус: доза единственная, что человек
/// даёт сам по расписанию, и её строку ищут глазами среди бытовых.
///
/// ## Цвета приехали токенами в ходе смены — и это перемер, а не память
///
/// Первый замер 22.10.2026 (утро) дал **ноль**: девяти цветов
/// `category.*` не было ни в `DesignTokens/tokens.json`, ни в Swift,
/// оба канала с живым контролем. К середине дня владелец токенов завёл
/// `Token.Component.CategoryBadge` — перемер нашёл все девять плюс
/// размер, радиусы и пару для инцидента.
///
/// > Утверждение «токенов нет» было верным в момент записи и протухло
/// > за несколько часов. Поэтому сюда вписан не вывод, а **способ
/// > проверить**: `grep -n "enum CategoryBadge" TogoShared/Generated/Tokens.generated.swift`.
///
/// Литералом цвет не вписан ни разу: `DesignLiteralTests` держит его
/// в слое вида на строгом нуле, и продуктовый цвет, записанный литералом,
/// **в повышенный контраст не попадает вовсе**
/// (`.claude/rules/токены-и-дизайн.md`).
struct CategoryBadge: View {
    let kind: LogKind
    /// Кровь и рвота поднимают бытовую запись в тревожное. Признак тот же,
    /// что у `LogEvent.titleColor`, и спрашивается он у события, а не
    /// выводится из вида: «стул» бывает и обычным, и с кровью.
    var raisesAlarm: Bool = false
    /// Пока висит тост «Отменить», строка стоит погашенной — это вторая
    /// половина кнопки отмены.
    var isDeleted: Bool = false

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.semibold))
            .foregroundStyle(значок)
            .frame(width: Token.Size.avatarMd, height: Token.Size.avatarMd)
            .background(заливка, in: форма)
            // Значок дублирует заголовок строки, и озвучке он не нужен:
            // подпись собирает сама строка через `accessibilityElement`.
            .accessibilityHidden(true)
    }

    /// Доза — скруглённый квадрат, всё остальное — круг.
    ///
    /// Одной фигурой, а не парой `Circle()` / `RoundedRectangle()`:
    /// у `background(_:in:)` тип фигуры один на оба случая, и радиус
    /// в половину стороны даёт ровно круг. Так форма остаётся **одним**
    /// решением, а не развилкой в двух местах.
    private var форма: RoundedRectangle {
        RoundedRectangle(cornerRadius: радиус, style: .continuous)
    }

    private var радиус: CGFloat {
        kind == .dose ? Token.Radius.small : Token.Size.avatarMd / 2
    }

    /// Инцидент — единственная категория, у которой цвет УЖЕ есть.
    ///
    /// Хендофф задаёт ему `status.error` с белым значком. Берём здешнюю
    /// пару тревоги (`overdueBg` + `overdueText`): она прошла
    /// `contrast_graphite.py` во всех четырёх режимах, а белое по
    /// `status.error` у нас не меряно ни разу. Расхождение с хендоффом
    /// названо в отчёте, а не замазано.
    /// **`Token.Surface.pressed` здесь НЕ берётся, и это замер, а не вкус.**
    ///
    /// Прототип кладёт погашенной строке `surface-pressed`, и прямой
    /// перенос стоил бы красного сторожа всем: `ThemeContrastTests:514`
    /// считает читателей `Token.Surface.pressed` в коде продукта и
    /// краснеет на первом же — потому что эта роль и заливка выключенной
    /// кнопки сидят на одном примитиве `night5` и обязаны разойтись
    /// в тот момент, когда читатель появится (решение Виктории 15.10.2026).
    /// Замер 22.10.2026: живых читателей по-прежнему ноль при живом
    /// контроле `Surface.sunken`. Разводить два токена — работа владельца
    /// токенов, не моя, и до неё погашенное берёт `sunken`.
    private var заливка: Color {
        if isDeleted { return Token.Surface.sunken }
        if kind == .incident || raisesAlarm { return Token.Status.overdueBg }
        return ждётТокена
    }

    private var значок: Color {
        if isDeleted { return Token.Ink.secondary }
        if kind == .incident || raisesAlarm { return Token.Status.overdueText }
        return Token.Ink.primary
    }

    /// Заливка на время, пока цвета категории не заведены.
    ///
    /// Перечисление **полное и нарочно без `default`**: придёт
    /// `Token.Category.*` — компилятор приведёт сюда по одному случаю
    /// за раз. С `default` новый вид записи молча получил бы серый,
    /// и это читалось бы как «цвет у него такой», а не «цвета нет».
    ///
    /// Имена справа — то, что ждёт каждый случай
    /// (`togo-ios28.tokens.json`, ключ `category`):
    ///
    ///     walk · outing   category.walk    #7CE0A0
    ///     stool           category.poop    #A2C1FE
    ///     meal            category.food    #FF9A5C
    ///     treat           category.treat   #FF9A5C
    ///     water           category.water   #7FD3FF
    ///     dose            category.dose    #FF8FBF
    ///     training        category.train   #C3A6FF
    ///     care            category.care    #C3A6FF
    ///     weight          category.weight  #FFD43B
    ///
    /// Четыре вида записи в хендоффе не названы вовсе — `reaction`,
    /// `travelStop`, `note` и `incident` (у последнего цвет есть, но
    /// отдельным ключом). В прототипе они падают в `surface-pressed`
    /// со значком `text-secondary`, то есть «категории нет», и это
    /// решение, а не пропуск: `CC[e.type] || 'var(--surface-pressed)'`.
    /// Здесь вместо него `sunken` — по причине, написанной у `заливка`.
    ///
    /// **`outing` в хендоффе тоже нет, и он приписан к `walk` мной.**
    /// Основание не «похоже», а словарь продукта: `TimelineBlock.isOuting`
    /// считает выходом и прогулку, и выход по нужде, и строка «дома 3 ч»
    /// меряется между ними обоими. Оставить выход серым значило бы
    /// покрасить половину одного домена.
    private var ждётТокена: Color {
        switch kind {
        case .walk, .outing, .stool, .meal, .treat, .water,
             .dose, .training, .care, .weight:
            Token.Surface.control
        case .reaction, .travelStop, .note, .incident:
            Token.Surface.sunken
        }
    }
}
