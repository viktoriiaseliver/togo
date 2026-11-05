import SwiftUI

/// Figma: `SectionHeader`. Заглавная микро-строка над группой.
struct TGSectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(title)
                .textStyle(AppFont.caps)
                .textCase(.uppercase)
                .kerning(0.6)
                .wraps()
            if let subtitle {
                Text(subtitle)
                    .textStyle(AppFont.caption)
                    .wraps()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Figma: `Explainer`. Объяснение стоит там, где возникает вопрос —
/// отдельной справки в приложении нет и не нужно.
///
/// # Памятка: объяснение, которое перестаёт повторяться
///
/// Просьба Виктории 29.10.2026: «чтобы разные шторки не показывались
/// миллион раз, которые несут только информацию». «Просится», «Как
/// сходил?», «Что случилось» открываются по десять раз в день, и одно
/// и то же «запишется сразу, без вопросов» на десятый раз — уже шум
/// между человеком и кнопкой.
///
/// Объяснение с ключом `памятка` показывается первые
/// `Памятки.сколькоРаз` появлений и дальше не рисуется. Без ключа —
/// всегда, как прежде: объяснение СОСТОЯНИЯ («доза откроется
/// в 18:30», «кровь поднимает запись») нужно каждый раз, потому что
/// каждый раз оно про другое.
struct TGExplainer: View {
    let text: LocalizedStringKey
    /// Ключ памятки. Пусто — объяснение показывается всегда.
    var памятка: String?

    /// Решено при появлении, а не на каждом `body`: иначе счётчик,
    /// увеличенный в `onAppear`, прятал бы текст прямо на глазах.
    @State private var видна: Bool

    init(text: LocalizedStringKey, памятка: String? = nil) {
        self.text = text
        self.памятка = памятка
        _видна = State(initialValue: Памятки.видна(памятка))
    }

    var body: some View {
        if видна {
            Text(text)
                .textStyle(AppFont.caption)
                .wraps()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { Памятки.показана(памятка) }
        }
    }
}

/// Сколько раз памятка уже показана — по ключу, на этом телефоне.
///
/// `UserDefaults`, а не база: это удобство вида, а не запись дневника,
/// и уезжать второму человеку оно не должно — у мамы свои первые три раза.
enum Памятки {
    static let сколькоРаз = 3

    private static func ключ(_ памятка: String) -> String { "памятка.\(памятка)" }

    static func видна(_ памятка: String?) -> Bool {
        guard let памятка else { return true }
        return UserDefaults.standard.integer(forKey: ключ(памятка)) < сколькоРаз
    }

    static func показана(_ памятка: String?) {
        guard let памятка else { return }
        let k = ключ(памятка)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: k) + 1, forKey: k)
    }

    /// Вернуть все памятки — для «Настроек», если человек захочет
    /// перечитать объяснения.
    static func сбросить() {
        for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix("памятка.") {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}

/// Figma: `ListRow`. Свойства — `title`, `value`, `systemImage`, `accessory`, `tone`.
struct TGListRow: View {
    enum Accessory: Sendable { case chevron, checkmark, none }

    @Environment(\.theme) private var theme
    /// Настройка размера текста: от неё зависит, строкой или столбцом
    /// раскладывать подпись и значение.
    @Environment(\.dynamicTypeSize) private var размерТекста

    let title: LocalizedStringKey
    var value: LocalizedStringKey?
    var systemImage: String?
    var accessory: Accessory = .chevron
    var tone: Color = Token.Ink.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.s12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Token.Size.iconMd, weight: .medium))
                    .foregroundStyle(Token.Ink.secondary)
                    .frame(width: Token.Space.s24)
                    .accessibilityHidden(true)
            }

            // При крупной системной настройке подпись и значение встают
            // друг под друга, а не ужимаются до нечитаемого.
            //
            // **Раскладка выбирается явным `if`, а не `ViewThatFits`:**
            // он запрещён красной линией проекта — держал в дереве ОБЕ
            // ветки, и озвучка находила по два элемента на один орган.
            // Здесь это значило бы две копии подписи строки настроек,
            // а `TGListRow` зовёт каждая строка настроек.
            //
            // И вопрос у двух способов разный: `ViewThatFits` решает
            // по МЕСТУ, а доступность — по НАСТРОЙКЕ человека. Совпадают
            // они случайно и расходятся на узком экране с крупным
            // кеглем, то есть ровно там, где человеку труднее всего.
            if размерТекста.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    titleText
                    valueText
                }
                // **Отзыв «Съехала стрелочка» (сб141, 23.09) — вот он.**
                // Распорки в этой ветке нет: `VStack` сжимается
                // до ширины своего текста, и `accessoryView` — сосед
                // по ВНЕШНЕМУ `HStack` — встаёт вплотную к тексту
                // посреди строки вместо правого края. На кадре это была
                // единственная двухстрочная строка списка «Здоровье»
                // и единственная съехавшая.
                //
                // Автор прежнего комментария знал про крупный шрифт
                // и обработал перенос; шеврон остался без распорки
                // потому, что лежал ВНЕ того, что он правил. Чинить
                // надо не ветку, а ВСЕ ветки и всех соседей
                // по внешнему контейнеру.
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Token.Space.s8) {
                    titleText
                    // Распорка: она же растягивает строку до правого края,
                    // и потому шеврон стоит справа.
                    Spacer(minLength: Token.Space.s8)
                    valueText
                }
            }

            accessoryView
        }
        .frame(minHeight: Token.Size.tapTarget)
        .padding(.vertical, max(0, theme.density.rowPadding - Token.Space.s12))
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .textStyle(AppFont.body.color(tone))
            .wraps()
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .textStyle(AppFont.caption)
                .wraps()
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        // Шеврон и галочка ничего не добавляют голосом: состояние строки
        // читается из её текста.
        switch accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: Token.Size.iconSm, weight: .semibold))
                .foregroundStyle(Token.Ink.secondary)
                .accessibilityHidden(true)
        case .checkmark:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Token.Size.iconMd, weight: .semibold))
                .foregroundStyle(Token.Action.doneText)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }
}

/// Figma: `Stat`. Число и подпись. Счётчики не украшены иконками и не раскрашены.
struct TGStat: View {
    let value: String
    let caption: LocalizedStringKey
    var size: CGFloat = 22

    /// Счётная подпись: число крупно, слово в верной форме мелко.
    ///
    /// **Заведено 07.10.2026, потому что подписи не склонялись нигде.**
    /// Кадр галереи итога прогулки показал «1 срывов»: `caption`
    /// — обычная строка, и о числе в `value` она не знает ничего.
    /// Верно выходило только от пяти и больше.
    ///
    /// Приём в проекте УЖЕ БЫЛ — `TodaySummaryStrip.подпись(_:_:)`
    /// берёт переведённую строку с числом и отрезает число, иначе
    /// выходит «3 3 выхода». Но жил он **приватно в одном файле**,
    /// и остальные счётные подписи его не знали: «1 записей»,
    /// «1 собак», «1 действий», «1 попыток».
    ///
    /// > Приём, решённый в одном месте и не вынесенный, — это
    /// > починка на одной поверхности из скольких-то. Он не защищает
    /// > даже себя: следующий вызов пишется рядом и мимо.
    ///
    /// Поэтому отрезание живёт здесь, у компонента, а не у экрана.
    ///
    /// **Строка приходит УЖЕ локализованной и уже с числом**, а не
    /// ключом. Первая редакция брала `String.LocalizationValue`
    /// и локализовала внутри — и это не выбрало бы форму вовсе:
    /// без интерполяции в ключе нет аргумента, по которому каталог
    /// различает «срыв», «срыва» и «срывов». Число обязано попасть
    /// в ключ на месте вызова: `String(localized: "\(n) срывов")`.
    ///
    /// Swift правил склонения не знает и знать не должен — форму
    /// выбирает каталог.
    init(count: Int, сЧислом: String, size: CGFloat = 22) {
        self.value = "\(count)"
        // НЕ `String(localized:)` у разделителя: это не текст
        // для человека, а кусок для отрезания от уже переведённой
        // строки. Перевод подставил бы чужой разделитель, и число
        // осталось бы в подписи — так уже было 28.09.
        self.caption = LocalizedStringKey(
            сЧислом.replacingOccurrences(of: "\(count) ", with: ""))
        self.size = size
    }

    init(value: String, caption: LocalizedStringKey, size: CGFloat = 22) {
        self.value = value
        self.caption = caption
        self.size = size
    }

    var body: some View {
        VStack(spacing: Token.Space.s2) {
            Text(value)
                .textStyle(AppFont.numeric(size))
                .lineLimit(1)
                // Число лучше показать чуть мельче, чем обрезать: «190 мл»
                // с многоточием не читается вообще.
                .minimumScaleFactor(0.6)
            Text(caption)
                .textStyle(AppFont.micro)
                .multilineTextAlignment(.center)
                // Колонка узкая: три подписи делят ширину карточки.
                // На крупной системной настройке «кормление» ломалось
                // посреди слова — «кормл / ение» на кадре 28.09.
                // Перенос внутри слова хуже мелкого шрифта: слово
                // перестаёт узнаваться, а число над ним теряет подпись.
                //
                // Ограничение строк здесь ОБЯЗАТЕЛЬНО: без него
                // `minimumScaleFactor` не работает вовсе — текст, которому
                // разрешено расти вниз, ужимать нечего. `wraps()` как раз
                // и снимал ограничение, поэтому первая правка не помогла.
                // Три строки, а не две: на крупной настройке подпись
                // из двух слов в двух строках не помещается, и остаток
                // уходил в соседнюю колонку.
                .lineLimit(3)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        // Жёлоб между колонками. Без него подписи соседних чисел
        // СОПРИКАСАЛИСЬ: кадр 28.09 на «Питании» — «из 2 кормлений»
        // упиралось в «осталось», и две подписи читались как одна
        // фраза. Три колонки длинных русских слов в четырёхстах точках
        // не помещаются по устройству; жёлоб лечит слипание, а не
        // тесноту.
        //
        // НЕ ПОЧИНЕНО и названо: на доступных размерах ряду из трёх
        // чисел нужна другая раскладка — столбцом, как у плиток
        // и карточки дежурства. Мест таких двенадцать, и это отдельная
        // работа, а не довесок к этой.
        .padding(.horizontal, Token.Space.s4)
        .accessibilityElement(children: .combine)
    }
}

/// Figma: `Avatar`. Свойства — `initial`, `image`, `size`, `tint`.
struct TGAvatar: View {
    var initial: String
    var image: Data?
    var size: CGFloat = Token.Size.avatarSm
    var tint: Color = Token.Action.done

    var body: some View {
        Group {
            if let image, let uiImage = КэшСнимков.картинка(image) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Подпись на аватаре.
    ///
    /// Раньше цвет выбирался сравнением тинта с двумя конкретными
    /// токенами: поменяешь тинт — и подпись молча станет нечитаемой.
    /// В тёмном наборе все аватарные фоны тёмные, поэтому подпись
    /// всегда основным цветом текста.
    private var foreground: Color { Token.Ink.primary }
}

/// Figma: `Author`. Кто записал.
///
/// Раньше здесь была ещё и зелёная галочка «синхронизировано» — у каждой
/// записи, всегда. Обмен между устройствами с тех пор появился, но
/// доставку **конкретной строки** он не отслеживает: `isSynced` по-прежнему
/// всегда `true`. То есть галочка так и осталась бы украшением,
/// притворяющимся сведениями, — вернётся, когда будет что показывать.
///
/// Инициал автора остаётся, но только когда в семье больше одного
/// человека: одному себе представляться незачем.
struct TGAuthorMark: View {
    let author: String

    var body: some View {
        Text(String(author.prefix(1)))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Token.Ink.secondary)
            .accessibilityLabel(Text("Записала \(author)"))
    }
}
