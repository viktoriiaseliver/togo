import Foundation

/// Норма показателя и отклонение от неё. Медицинский слой,
/// `docs/ТЗ-медицинский-слой.md` §2.1 и §3.4.
///
/// Два требования ТЗ, и оба про то, чего делать НЕЛЬЗЯ:
///
/// > **Отклонение считается, а не вводится.** Иначе оно разойдётся
/// > со значением при первой же правке.
///
/// > **Не придумывать значения.** Если норма показателя неизвестна —
/// > «норма не указана», а не подставленная из интернета.
///
/// Отсюда устройство: норма — это **либо диапазон, либо порог, либо
/// её нет**, и третий случай полноправный. Приложение не ставит
/// диагнозов; оно говорит «ниже нормы» только когда норма есть.
nonisolated enum LabNorm {

    /// Как норма записана в бланке. Из настоящей карты Стича:
    /// `12,9–51,5` у Т4 и `<0,50` у ТТГ.
    enum Reference: Sendable, Equatable {
        /// Диапазон. У Т4 норма 12,9–51,5 — это диапазон, и линией
        /// его рисовать нельзя (ТЗ §3.2: «норма — полосой фона»).
        case range(low: Double, high: Double)
        /// Только верхний порог: `<0,50`.
        case upperBound(Double)
        /// Только нижний порог.
        case lowerBound(Double)
        /// Нормы нет. Не «ноль» и не «любое» — именно нет.
        case unknown
    }

    /// Значение из бланка.
    ///
    /// **Отдельный случай `belowDetectionLimit` не формальность.** ТЗ
    /// называет живой пример: `<0,1 нг/дл`. Это не число 0,1 — это
    /// «меньше, чем прибор умеет различить». Записав его как 0,1,
    /// получим тихо неверное число вместо видимо неизвестного —
    /// ровно то, за что у Kvit записано «отказ бывает правильным
    /// поведением».
    enum Value: Sendable, Equatable {
        case measured(Double)
        /// Ниже предела обнаружения: `<0,1`.
        case belowDetectionLimit(Double)
        /// Выше предела обнаружения: `>10`.
        case aboveDetectionLimit(Double)
    }

    /// Куда попало значение.
    enum Deviation: Sendable, Equatable {
        case below
        case withinRange
        case above
        /// Сравнить не с чем: нормы нет.
        case normUnknown
        /// Значение за пределом прибора, и норма этого предела
        /// не разрешает: сказать «ниже» нельзя, потому что неизвестно,
        /// насколько.
        case indeterminate
    }

    /// Терапевтический коридор — **вторая полоса, и у неё есть
    /// условие.** Заведено 07.10.2026 по замеру карты Стича.
    ///
    /// В бланках лежат две разные величины, и путать их нельзя:
    ///
    /// ```
    /// референс Т4 общий        12,9–51,5 нмоль/л    здоровая собака
    /// терапевтический коридор    27–69 нмоль/л      собака НА ЛЕЧЕНИИ,
    ///                                                и только через 4–6 ч
    ///                                                после приёма
    /// ```
    ///
    /// Т4 = 16,7 лежит **внутри референса и ниже коридора**. То есть
    /// по одной мерке «в норме», по другой «доза не работает», и это
    /// не придирка: ровно этим вопросом карта и велась.
    ///
    /// **Почему коридор живёт в норме, а не в схеме лечения.** Замер
    /// по карте: из 127 результатов схема известна у **восьми**.
    /// Положи коридор на схему — и остальные 119 молча откатятся
    /// на референс, то есть приложение скажет «в норме» про 16,7.
    /// **Ложное успокоение хуже молчания**, и в этом продукте
    /// особенно: его читают, когда с собакой что-то не так. Довод
    /// и число — `togo-05`, 07.10.
    struct TherapeuticBand: Sendable, Equatable {
        let low: Double
        let high: Double
        /// Окно после приёма, в котором коридор вообще что-то значит.
        /// У Т4 это 4–6 часов — вне него пик уже прошёл или ещё
        /// не наступил, и сравнивать с коридором нечего.
        let fromHoursAfterDose: Double
        let toHoursAfterDose: Double

        init(low: Double, high: Double,
             fromHoursAfterDose: Double, toHoursAfterDose: Double) {
            self.low = low
            self.high = high
            self.fromHoursAfterDose = fromHoursAfterDose
            self.toHoursAfterDose = toHoursAfterDose
        }

        /// Коридор Т4 из карты Стича. Числа из бланков, не из головы.
        static let totalT4 = TherapeuticBand(low: 27, high: 69,
                                             fromHoursAfterDose: 4,
                                             toHoursAfterDose: 6)
    }

    /// Чем прочитан результат. **Третий случай обязателен и он
    /// не отказ от ответа, а сам ответ.**
    enum Reading: Sendable, Equatable {
        /// Забор в окне коридора — читаем по коридору.
        case byTherapeuticBand(Deviation)
        /// Забор вне окна — читаем по референсу, и **говорим**, что
        /// коридор не про это время. Молча отдать референс значило бы
        /// выдать одну мерку за другую.
        case byReferenceOutsideWindow(Deviation)
        /// Часов не записано. Подставить «вероятно, 4–6» значило бы
        /// изобрести норму — тоньше, чем из интернета, но так же:
        /// из удобства.
        case bandNotApplied(Deviation)
        /// Лечения нет — коридора не существует, и вопроса тоже.
        case byReferenceNoTreatment(Deviation)
    }

    /// Прочитать результат с учётом коридора.
    ///
    /// `hoursAfterDose` приходит из `LabSampleTiming` — там же, где
    /// живут три состояния времени забора, и повторять их здесь
    /// нельзя: два правила на одну мысль расходятся на второй правке.
    static func reading(value: Value,
                        reference: Reference,
                        band: TherapeuticBand?,
                        hoursAfterDose: Double?) -> Reading {
        guard let band else {
            return .byReferenceNoTreatment(deviation(value: value, from: reference))
        }
        guard let hours = hoursAfterDose else {
            return .bandNotApplied(deviation(value: value, from: reference))
        }
        guard hours >= band.fromHoursAfterDose, hours <= band.toHoursAfterDose else {
            return .byReferenceOutsideWindow(deviation(value: value, from: reference))
        }
        return .byTherapeuticBand(
            deviation(value: value, from: .range(low: band.low, high: band.high)))
    }

    /// Чем прочитано — словом. Четыре исхода, четыре разные новости;
    /// одним текстом их покрывать нельзя, за это у Togo уже заплачено
    /// ступенью отката iCloud.
    static func readingWord(_ reading: Reading) -> String {
        switch reading {
        case .byTherapeuticBand(let d):
            word(d)
        case .byReferenceOutsideWindow:
            String(localized: "забор вне окна 4–6 ч — читается по обычной норме")
        case .bandNotApplied:
            String(localized: "не записано, через сколько часов после дозы")
        case .byReferenceNoTreatment(let d):
            word(d)
        }
    }

    /// Отклонение. Чистая функция — её можно спросить из теста.
    ///
    /// Порядок проверок — часть смысла: **сперва «есть ли норма»,
    /// потом «есть ли число».** Обратный порядок дал бы «в норме»
    /// на значении без нормы.
    static func deviation(value: Value, from reference: Reference) -> Deviation {
        guard reference != .unknown else { return .normUnknown }

        switch value {
        case .measured(let number):
            switch reference {
            case .range(let low, let high):
                if number < low { return .below }
                if number > high { return .above }
                return .withinRange
            case .upperBound(let high):
                return number > high ? .above : .withinRange
            case .lowerBound(let low):
                return number < low ? .below : .withinRange
            case .unknown:
                return .normUnknown
            }

        case .belowDetectionLimit(let limit):
            // `<0,1` ниже нормы только если сам предел не выше её низа.
            // Иначе «меньше 0,1» могло бы лежать и в норме, и под ней.
            switch reference {
            case .range(let low, _):
                return limit <= low ? .below : .indeterminate
            case .lowerBound(let low):
                return limit <= low ? .below : .indeterminate
            case .upperBound:
                // «Меньше чего-то» при норме «меньше порога» — в норме,
                // если предел прибора не выше порога.
                return .withinRange
            case .unknown:
                return .normUnknown
            }

        case .aboveDetectionLimit(let limit):
            switch reference {
            case .range(_, let high):
                return limit >= high ? .above : .indeterminate
            case .upperBound(let high):
                return limit >= high ? .above : .indeterminate
            case .lowerBound:
                return .withinRange
            case .unknown:
                return .normUnknown
            }
        }
    }

    /// Отклонение словом. ТЗ §3.2: «направление отклонения **не только
    /// цветом** — у каждой точки вне нормы подпись словом, иначе её
    /// не услышит VoiceOver и не увидит дальтоник».
    ///
    /// Поэтому слово живёт рядом с правилом, а не во вью: иначе вторая
    /// поверхность напишет своё. У Togo уже было — виджет считал окно
    /// «не кормить» своей арифметикой.
    static func word(_ deviation: Deviation) -> String {
        switch deviation {
        case .below: String(localized: "ниже нормы")
        case .withinRange: String(localized: "в норме")
        case .above: String(localized: "выше нормы")
        case .normUnknown: String(localized: "норма не указана")
        case .indeterminate: String(localized: "сравнить нельзя")
        }
    }

    /// Можно ли вообще нарисовать полосу нормы.
    ///
    /// Нужно графику: у порога полоса односторонняя, у диапазона
    /// двусторонняя, а без нормы её нет — и это не повод не рисовать
    /// точки.
    static func bandBounds(_ reference: Reference) -> (low: Double?, high: Double?)? {
        switch reference {
        case .range(let low, let high): (low, high)
        case .upperBound(let high): (nil, high)
        case .lowerBound(let low): (low, nil)
        case .unknown: nil
        }
    }
}
