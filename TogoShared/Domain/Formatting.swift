import Foundation

nonisolated enum Fmt {

    // MARK: Кличка

    /// Кличка, годная для показа, — или `nil`.
    ///
    /// **Единственная реализация правила «что считать кличкой».**
    /// Её зовут `Dog.nameIfAny` и `Dog.displayName`
    /// (все поверхности приложения), `DogPayload.hasUsableName` (приём
    /// снимка из общего дневника и восстановление архива), `SnapshotText`
    /// и `TodayWidgetView` («остров», виджет, экран блокировки).
    ///
    /// **Почему правило живёт здесь, а не на `Dog`.** У виджета модели
    /// нет вовсе: ему достаётся снимок с полем `dogName: String`,
    /// записанный приложением раньше — может быть, прошлой сборкой.
    /// Правило, доступное только через модель, до него не дотянулось бы,
    /// и у «острова» завелась бы вторая реализация. У нас записано
    /// и оплачено: третья реализация одного правила молчала в двух
    /// случаях из трёх.
    ///
    /// Пробелы снимаются вместе с переводами строк и неразрывным
    /// пробелом U+00A0 — последний приезжает опечаткой с французской
    /// клавиатуры и рисуется ровно так же пусто, как `""`.
    /// Имя латиницей — след обхода, который **уже не нужен**, и это
    /// честнее, чем переименовать обратно.
    ///
    /// Первая редакция звалась `Fmt.кличка` и дала два ложных
    /// срабатывания в `LocalizationDebtTests`: тот разбирал литералы
    /// посимвольно и считал кириллицу внутри `"…\(…)…"` непереведённой
    /// строкой. Тогда функцию переименовали, а сторожа оставили как был.
    ///
    /// **Сторож починен в тот же день**: тело интерполяции он теперь
    /// разбирает рекурсивно, как код, и у него есть тест на самого себя
    /// (`разборРазличаетКодИСтроку`). То есть кириллическое имя здесь
    /// снова законно.
    ///
    /// Переименовывать обратно я не стал: тридцать три поверхности
    /// ради вкуса — чужой риск без выгоды. Но причина осталась
    /// записанной, чтобы следующий не считал латиницу здесь правилом
    /// проекта.
    static func dogName(_ raw: String) -> String? { notBlank(raw) }

    /// Непустое значение — или `nil`.
    ///
    /// **То же правило, что у клички, но у него нашлись другие
    /// хозяева.** 07.10.2026 перечисление группировок показало, что
    /// по полю со значением по умолчанию склеиваются не только собаки:
    /// имя участника семьи, место и человек у шага дрессировки — все
    /// `String = ""`. Поэтому правило живёт отдельно от `dogName`,
    /// а `dogName` стала его именем для случая собаки: имя у места
    /// вызова важнее, чем экономия строки.
    static func notBlank(_ raw: String) -> String? {
        let чистая = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return чистая.isEmpty ? nil : чистая
    }

    /// То же, но с запасным словом из каталога.
    ///
    /// `String(localized:)` **внутри** функции, а не литералом на месте
    /// вызова: возвращается ЗНАЧЕНИЕ типа `String`, и `Text(значение)`
    /// рисует его мимо каталога локализации. Напиши литерал снаружи —
    /// и француз прочтёт русское слово на объявлении о пропаже собаки.
    /// **ЗАПАСНОЕ СЛОВО ЧЕРНОВОЕ — до правки текстов.** Решение
    /// Виктории 07.10.2026: дизайн будет меняться, тексты сегодня
    /// не трогаем. Слово взято самое скучное и уже лежавшее
    /// в каталоге, чтобы не заводить новый вариант. Форма слова
    /// по поверхностям («Собака» в заголовке, «с собакой» в строке) —
    /// текстовая работа, и она НЕ сделана.
    ///
    /// Найти при правке текстов: `grep ЧЕРНОВОЕ-ЗАПАСНОЕ-СЛОВО`.
    /// Пометка станет ложной ровно тогда, когда тексты поправят.
    static func dogNameOrFallback(_ raw: String) -> String {
        // ЧЕРНОВОЕ-ЗАПАСНОЕ-СЛОВО
        dogName(raw) ?? String(localized: "Собака")
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func clock(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide)) + " · " + date.formatted(.dateTime.day().month(.wide))
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// «5 ч 20 мин» — так же, как в макете, без «5:20:00».
    ///
    /// Единицы печатает система, а не мы. Раньше «ч» и «мин» были
    /// склеены литералами, и у француза выходило «5 ч 20 мин» при
    /// французском интерфейсе. Замер 23.09: системный вывод по-русски
    /// совпадает с прежним посимвольно — «25 мин», «2 ч», «5 ч 20 мин».
    static func duration(_ interval: TimeInterval) -> String {
        часыМинуты(секунд: max(0, Int(interval)))
    }

    /// Часы и минуты средствами системы: ноль-единицы прячем, чтобы
    /// «2 ч» не превращалось в «2 ч 0 мин».
    private static func часыМинуты(секунд: Int) -> String {
        Duration.seconds(секунд).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated,
                   maximumUnitCount: 2, zeroValueUnits: .hide))
    }

    /// Число с одним знаком после запятой — и без него, если знак нулевой.
    /// «4 раза в день» читается, «4,0 раза» выглядит отчётом.
    static func decimal(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Часы и минуты для героя.
    ///
    /// Секундомер здесь не годится — он считает минуты и секунды,
    /// и два с половиной часа превращались в «165:16».
    ///
    /// Раньше здесь стояло сокращение «м» вместо «мин» — решение
    /// макета. Оно стоило локализации: собрать «2 ч 12 м» на любом
    /// языке, кроме русского, нечем. Единицы печатает система.
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        часыМинуты(секунд: max(0, Int(interval) / 60) * 60)
    }

    /// Порядковое числительное для строки «третий раз за шесть часов».
    ///
    /// Дальше десятого не идём: если рвота случилась одиннадцать раз,
    /// человек уже в клинике, а не читает подпись.
    static func ordinal(_ value: Int) -> String {
        let words = ["", String(localized: "первый"), String(localized: "второй"), String(localized: "третий"), String(localized: "четвёртый"), String(localized: "пятый"),
                     String(localized: "шестой"), String(localized: "седьмой"), String(localized: "восьмой"), String(localized: "девятый"), String(localized: "десятый")]
        return words.indices.contains(value) ? words[value] : String(localized: "\(value)-й")
    }

    /// Промежуток для ленты: коротко и без ложной точности.
    ///
    /// «4 ч 58 мин» между записями — это точность, которой там неоткуда
    /// взяться и которая никому не нужна: промежуток читают глазами,
    /// чтобы понять порядок величины. Округляем до получаса, а после двух
    /// часов минуты выбрасываем совсем.
    static func gap(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 90 { return String(localized: "\(minutes) мин") }

        let hours = Double(minutes) / 60
        if minutes >= 120 { return часыМинуты(секунд: Int(hours.rounded()) * 3600) }

        // Округление осталось прежним, сменилась только печать: считаем
        // получасами, а единицы называет система.
        let half = (Double(minutes) / 30).rounded() * 30
        return часыМинуты(секунд: Int(half) * 60)
    }

    static func stopwatch(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Вес: единицу и разделитель дробной части выбирает система.
    /// Было `String(format: "%.1f кг")` с ручной заменой точки на запятую —
    /// и «кг» намертво по-русски.
    static func weight(_ kg: Double) -> String {
        Measurement(value: kg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated,
                                    usage: .personWeight,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }


    static func days(_ n: Int) -> String { String(localized: "\(n) дней") }
    static func outings(_ n: Int) -> String { String(localized: "\(n) выходов") }
    static func minutes(_ n: Int) -> String { String(localized: "\(n) минут") }
    static func times(_ n: Int) -> String { String(localized: "\(n) раз") }
    static func records(_ n: Int) -> String { String(localized: "\(n) записей") }
    static func actions(_ n: Int) -> String { String(localized: "\(n) действий") }
}
