import SwiftUI
import WidgetKit

/// Вид виджета «сегодня» — вынесен из `TogoWidgets` 05.10.2026,
/// переписан под «Кино» (iOS 28) 23.10.2026.
///
/// **Зачем переезд.** Виджет рисует SpringBoard, и `app.screenshot()`
/// до него не достаёт: три поверхности правила тишины (виджет,
/// «остров», лист вердикта) были закрыты сторожем только на уровне
/// строк. «Что человек УВИДИТ» не проверял никто, и не по недосмотру —
/// **смотреть было не на что**.
///
/// > Прежде чем проверять поверхность, проверь, что её МОЖНО проверить.
/// > Поверхность без кадра — не «непроверенная», а «непроверяемая»,
/// > и первое лечится взглядом, второе только переделкой входа.
///
/// **Семейство приходит значением, а не из среды.** `@Environment(\.widgetFamily)`
/// вне виджета не задать ничем надёжным, и вью, читающая его сама,
/// остаётся непроверяемой даже после переезда. Среду читает тонкая
/// обёртка на стороне `TogoWidgets`, здесь — обычный параметр.
///
/// **`now` тоже параметром.** Внутри стоял `Date()`, и строка про еду
/// меняла бы кадр каждый час: кадр, который нельзя повторить, нельзя
/// и сравнить.
///
/// ## Раскладка «Кино» — откуда числа
///
/// Эталон — `Дизайн/эталонные-кадры/ios28-кино-22.10/screenshots/16.png`,
/// разметка — `Дизайн/редизайн-ios28/prototypes/Togo-RU.dc.html:326-330`.
///
/// ```
/// шапка плитки     13 / 600, Ink.secondary, значок 18, зазор 6
/// крупное число    40 / вес 300 / Rounded / tabular, line-height 1
/// подпись низа     13, Ink.secondary
/// отступ плитки    14          радиус 24 (ставит система виджета)
/// средний виджет   подпись 13/600 secondary + значение 17/600
/// ```
///
/// **Вес 300 у крупного числа — исключение, записанное решением:**
/// «Время и важные значения — всегда semibold», и тут же «Крупные
/// показания Rounded 300 — исключение» (`Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`).
///
/// ## Чего в этой раскладке НЕТ, и почему это решения
///
/// **Полосы-косточки нет.** В макете под числом лежит полоса
/// (`width:{{ b.pct }}`, заливка `var(--text-link)` = `#A2C1FE`).
/// У полосы нужен **знаменатель** — сколько времени считается полным
/// интервалом между выходами. В снимке его нет, и вывести его здесь
/// было бы третьей реализацией правила: Того уже обжигался на том,
/// что виджет считал окно «не кормить» собственной арифметикой
/// и молчал в двух случаях из трёх. В прототипе `pct` приходит
/// из панели показания «Сегодня» (`ReadingTone`), то есть считает
/// его приложение. **Появится в снимке процент — полоса станет
/// пятью строками.**
///
/// **Плитки «Доза» нет.** В макете вторая плитка — час дозы
/// и «левотироксин 0,1 мг». В `WidgetSnapshot` про лекарства нет
/// ни одного поля (замер 23.10: `dose|доза|drug|medic` → 0 вхождений
/// при контроле `walk` → 7). Нарисовать её значило бы завести
/// **механизм без входа**, а подставить дозу — нарушить красную линию
/// «не подставлять там, где подстановка станет утверждением человека»:
/// запись потом читает врач.
///
/// **Кнопки «Гулять» нет.** `Button(intent:)` требует, чтобы тип
/// интента был собран В РАСШИРЕНИИ. `StartWalkIntent` живёт
/// в `Togo/Intents/WalkIntents.swift`, то есть в приложении, и тянет
/// за собой `Persistence`, `ModelContext` и `QuickLog`. Перенести его
/// в общий слой значит завести SwiftData в расширение — а это прямо
/// отменяет записанное устройство: «виджет не лезет в базу… так виджет
/// не зависит от схемы SwiftData и не может подвиснуть на миграции».
/// Второй путь — `Link` на `togo://walk`, но такой ссылки приложение
/// не обрабатывает (`RootView:139` знает только `join`), и кнопка
/// **открывала бы приложение**, чего макет как раз не обещает.
/// Оба пути меняют чужие решения — **называю, а не выбираю молча.**
struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    var now: Date = Date()

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(SnapshotText.inlineText(snapshot))
        case .accessoryRectangular:
            // Аксессуары локскрана система рисует своим вибрантным
            // монохромом: наши цвета туда не доезжают как цвета,
            // и красить их значило бы объявить управление, которого нет.
            // Поэтому здесь только иерархия кеглей, без токенов цвета.
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.verdictTitle).font(.headline)
                Text(SnapshotText.sinceText(snapshot)).font(.caption)
                Text(SnapshotText.mealLine(snapshot, now: now)).font(.caption2)
            }
        case .systemMedium:
            средний
        default:
            малый
        }
    }

    // MARK: - Что показывает крупное число

    /// Три состояния с числом и одно без него.
    ///
    /// **Порядок не случаен.** Идущий выход старше всего: он
    /// единственный меняется ежесекундно и единственный говорит
    /// «прямо сейчас». Дальше — время с последнего выхода, ради
    /// которого плитка и нарисована в макете. Если не отмечали
    /// ни разу, числа нет вовсе, и плитка переходит на слова: это
    /// та самая ступень тишины, ради которой заводилась галерея.
    private enum Показание {
        case наУлице(с: Date)
        case сПрогулки(с: Date)
        case словами
    }

    private var показание: Показание {
        if let начало = snapshot.walkStartedAt { return .наУлице(с: начало) }
        if let последний = snapshot.lastWalkAt { return .сПрогулки(с: последний) }
        return .словами
    }

    private var шапкаПлитки: (String, String) {
        switch показание {
        case .наУлице: (String(localized: "На улице"), "figure.walk")
        case .сПрогулки: (String(localized: "С прогулки"), "figure.walk")
        case .словами: (snapshot.verdictTitle, "pawprint")
        }
    }

    // MARK: - Малый

    private var малый: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            шапка
            Spacer(minLength: 0)
            крупное
            Spacer(minLength: 0)
            подписьНиза
        }
    }

    private var шапка: some View {
        let (текст, значок) = шапкаПлитки
        return HStack(spacing: Token.Space.s6) {
            Image(systemName: значок)
                .font(.system(size: 18, weight: .regular))
            Text(текст)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Token.Ink.secondary)
    }

    /// Крупное показание — или строка тишины, если считать нечего.
    ///
    /// **Ужимается, а не обрезается.** Выход дольше часа даёт «1:23:45»,
    /// а время с прогулки у заброшенного дневника — «434:10:…». Обрезка
    /// у часов превращает одно число в другое, и читается оно как
    /// правда; ужатие оставляет то же число мелким.
    @ViewBuilder
    private var крупное: some View {
        switch показание {
        case .наУлице(let с), .сПрогулки(let с):
            Text(с, style: .timer)
                .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(Token.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .словами:
            // Числа нет — и подставлять его неоткуда. Тишина говорится
            // словами той же функцией, что на локскране и в «острове»:
            // `sinceText` знает, что при отсутствии отметок печатается
            // дата, а не посчитанный интервал.
            Text(SnapshotText.sinceText(snapshot))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Token.Ink.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }

    /// Низ плитки: окно «не кормить» важнее строки про еду.
    ///
    /// Решение приезжает готовым: `fastingEndsAt` считает приложение
    /// тем же правилом, что и главный экран. Своей арифметики у виджета
    /// нет нарочно — на ней он однажды уже молчал в двух случаях из трёх.
    @ViewBuilder
    private var подписьНиза: some View {
        if let натощак = snapshot.fastingEndsAt, натощак > now {
            Label {
                // Через `String(localized:)` и `Fmt.clock`, а не
                // `Text(fasting, style: .time)`. Ключ получается тот же
                // (`не кормить до %@`), переводы уже лежат — но путь
                // в каталог теперь виден и сторожу, и человеку.
                Text(String(localized: "не кормить до \(Fmt.clock(натощак))"))
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Token.Status.waitingText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text(SnapshotText.mealLine(snapshot, now: now))
                .font(.system(size: 13))
                .foregroundStyle(Token.Ink.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Средний

    /// Средний виджет: слева подпись и значение, справа крупное число.
    ///
    /// Макет кладёт справа белую пилюлю «Гулять»; её здесь нет,
    /// и причина названа в голове файла. Пустое место отдано числу —
    /// тому же, что в малом, — чтобы средний отвечал на тот же вопрос
    /// крупнее, а не говорил меньше малого.
    private var средний: some View {
        HStack(alignment: .center, spacing: Token.Space.s12) {
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text(подписьДальше)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(snapshot.verdictTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.Ink.primary)
                    .lineLimit(2)
                подписьНиза
            }
            Spacer(minLength: Token.Space.s8)
            крупное
                .layoutPriority(1)
        }
    }

    /// «Стич · дальше» — кличка через `Fmt.dogName`, без именительного
    /// отката.
    ///
    /// `dogNameOrFallback` здесь не годится: «Собака · дальше» читается
    /// как вторая собака по имени «Собака», а не как отсутствие клички.
    /// Отзыв 06.10 был ровно про безымянные записи.
    private var подписьДальше: String {
        guard let кличка = Fmt.dogName(snapshot.dogName) else {
            return String(localized: "дальше")
        }
        return кличка + " · " + String(localized: "дальше")
    }
}
