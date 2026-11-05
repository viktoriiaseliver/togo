import SwiftUI

/// Мост между доменом и токенами.
///
/// Модели и логика про цвета не знают вообще: `SkillStatus` — это состояние
/// обучения, а не оттенок. Всё, что превращает домен в оформление, лежит здесь
/// одним файлом — так видно, что смысловых цветов ровно столько, сколько ролей.

extension SkillStatus {
    var tone: TGTone {
        switch self {
        case .notStarted: .neutral
        case .learning: .waiting
        case .works: .done
        }
    }

    var color: Color {
        switch self {
        case .notStarted: Token.Ink.secondary
        case .learning: Token.Status.waitingText
        case .works: Token.Action.doneText
        }
    }
}

extension MarkAccuracy {
    var color: Color {
        switch self {
        case .onTime: Token.Action.doneText
        case .almost: Token.Status.waitingText
        case .late: Token.Status.overdueText
        }
    }

    var tone: TGTone {
        switch self {
        case .onTime: .done
        case .almost: .waiting
        case .late: .alarm
        }
    }
}

extension StoolFlag {
    var tone: TGTone { raisesAlarm ? .alarm : .neutral }
}

extension LogEvent {
    /// Кровь — единственный флаг, поднимающий бытовую запись в терракот.
    var titleColor: Color { raisesAlarm ? Token.Status.overdueText : Token.Ink.primary }

    // `symbolColor` стоял здесь и удалён 27.10.2026. Это НЕ «правило
    // потеряли»: кровь доходит до цвета значка двумя живыми путями,
    // и оба спрашивают тот же `raisesAlarm`.
    //
    //     главная строка ленты     CategoryBadge.swift:104 и :137 —
    //                              заливка `Category.incident`,
    //                              чернила `Category.onIncident`
    //     отметка внутри прогулки  DayTimeline.swift:334, `цвет` —
    //                              overdueText ↔ Ink.secondary; ряд
    //                              рисует контейнер ленты
    //                              (DayTimeline:86; списочный
    //                              DayTimelineList удалён 05.11.2026)
    //
    // Замер: последний вызов жил в `efc38a4`
    // (`DayTimeline.swift:48 .foregroundStyle(event.symbolColor)`)
    // и исчез в `6fc8990` «Таймлайн глазами дизайнера»; с тех пор ноль
    // вызовов при живом контроле `titleColor` (DayTimeline.swift:164,
    // жив во всех тех же коммитах). Проверка за минуту:
    //     git grep -n "symbolColor"   ← ожидается только эта запись
    //     git grep -n "titleColor"    ← контроль, обязан найти вызов
    //
    // Подключать было не к чему, а третья редакция одного правила —
    // третье место, которое разойдётся молча: спокойный цвет у неё свой
    // (`Ink.silhouette`), и ни один из двух живых путей его не рисует,
    // то есть «подключение» было бы правкой ЦВЕТА без находки и без
    // кадра. `MarkGroup` вдобавок не `LogEvent` — позвать свойство
    // из ряда отметок нельзя, не переписав его.
}

extension NeedVerdict {
    /// Вердикт не красится в тревожное: «срочно» — это слово, а не красный экран.
    var tone: TGTone {
        switch self {
        case .urgent: .alarm
        case .likelyNeed: .waiting
        case .unknown, .probablyAttention, .episode: .neutral
        }
    }
}
