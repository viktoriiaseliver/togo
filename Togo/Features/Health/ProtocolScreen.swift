import SwiftUI
import SwiftData

/// Протокол контроля. Стартует от фактической отметки дозы и считает интервал сам —
/// именно отсутствие строки «доза → забор» дважды приводило к неверному чтению анализов.
struct ProtocolScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var lastDose: DoseRecord? {
        dog?.medications.flatMap(\.doses)
            .filter(\.isGiven)
            .max { ($0.givenAt ?? .distantPast) < ($1.givenAt ?? .distantPast) }
    }

    /// Назначенный контроль — дело ухода, которое ЕЩЁ НЕ ДЕЛАЛИ.
    ///
    /// **Отзыв 27.10.2026, 21:00: «не могу поставить на когда
    /// запланирован тест».** Экран считал только от ПОСЛЕДНЕЙ ДАННОЙ
    /// дозы: таблетка в 20:30 — значит «забор крови в 00:30», ночью.
    /// А забор назначен на 7 декабря днём, и сказать об этом экрану
    /// было нечем.
    ///
    /// Дата при этом уже лежала в дневнике — в деле ухода «Контроль
    /// общего Т4». Нового поля не понадобилось: нужен был читатель
    /// у того, что записано.
    ///
    /// Различитель «ещё не делали» — `lastDone == nil`: у прививки
    /// и обработки он стоит всегда (их делали хоть раз), у контроля,
    /// назначенного вперёд, пуст. Так его и заводит карта.
    private var назначенныйКонтроль: CareTask? {
        dog?.careTasks
            .filter { $0.deletedAt == nil && $0.lastDone == nil }
            .filter { ($0.scheduledDate ?? .distantPast) > Date() }
            .min { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    /// Час утренней дозы — от него считается забор в день анализа.
    ///
    /// Берётся у действующей схемы, а не задаётся числом: врач пишет
    /// «кровь через 4 часа после утреннего приёма», и если часы схемы
    /// поменяют, расчёт обязан поехать следом.
    private var утренняяДоза: Int? {
        dog?.medications
            .first { $0.cancelledAt == nil && !$0.isPaused }?
            .times.min()
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Протокол", отступы: false)
            if let dose = lastDose, let givenAt = dose.givenAt {
                TGCard {
                    Text("T+\(Fmt.duration(now.timeIntervalSince(givenAt)))").textStyle(AppFont.display)
                    Text("Доза дана в \(Fmt.clock(givenAt)) под наблюдением").textStyle(AppFont.caption)
                }
                TGCard(spacing: 0) {
                    ProtocolRow(label: "T0", time: givenAt,
                                title: "доза \(dog?.medications.first?.doseText ?? "")",
                                detail: "отмечено с точностью до минуты", isDone: true)
                    TGDivider()
                    // ГАЛОЧКА ЧИТАЕТ ОТМЕТКУ ЧЕЛОВЕКА, А НЕ ЧАСЫ.
                    //
                    // **Прежде здесь стояло `now > givenAt + 4 ч`** —
                    // то есть через четыре часа приложение само
                    // рисовало ✓ против «забор крови», сдавали кровь
                    // или нет. Отзыв 27.10.2026: «Не отмечается».
                    //
                    // > Это медицинская запись, показывающая галочку
                    // > за то, чего никто не делал. Красная линия
                    // > проекта названа дословно: «не подставлять там,
                    // > где подстановка станет утверждением человека».
                    // > Запись потом читает врач.
                    //
                    // Время осталось в строке — но как ПЛАН («в 13:30
                    // забор»), а не как факт.
                    ProtocolRow(label: "+4", time: givenAt.addingTimeInterval(4 * 3600),
                                title: "забор крови", detail: "напомним за 30 минут",
                                isDone: заборы(после: givenAt).count >= 1,
                                отметить: { recordDraw() })
                    TGDivider()
                    ProtocolRow(label: "+6", time: givenAt.addingTimeInterval(6 * 3600),
                                title: "забор крови", detail: "вторая точка, по назначению",
                                isDone: заборы(после: givenAt).count >= 2,
                                отметить: { recordDraw() })
                }
                TGCard {
                    Text("Интервал посчитаем сами").textStyle(AppFont.cardTitle)
                    Text("В отчёте будет строка «доза → забор: \(Fmt.duration(now.timeIntervalSince(givenAt)))». Без этой строки анализы уже дважды читали неверно.")
                        .textStyle(AppFont.caption)
                }
                TGButton(title: "Отметить забор крови", systemImage: "cross.vial") {
                    recordDraw()
                }
            } else {
                TGCard {
                    Text("Протокол начинается с дозы").textStyle(AppFont.cardTitle)
                    Text("Отметь приём препарата — приложение засечёт время и само посчитает +4 и +6 часов.")
                        .textStyle(AppFont.caption)
                }
            }
            планКонтроля
        }
        .navigationTitle("Протокол")
        .cinemaScreen(экран: .sub("protocol"))
        .onReceive(tick) { now = $0 }
    }

    /// Что будет в день назначенного забора.
    ///
    /// Показывается ВСЕГДА, когда контроль назначен, — и рядом
    /// с протоколом сегодняшней дозы тоже. Это два разных вопроса:
    /// «сколько прошло с утренней таблетки» и «когда вообще сдавать».
    /// До 28.10.2026 экран отвечал только на первый, и в обычный
    /// вечер отвечал бессмысленно: доза в 20:30 давала «забор крови
    /// в 00:30».
    ///
    /// Час забора считается от УТРЕННЕЙ дозы плюс четыре часа —
    /// так написано в выписке врача («кровь примерно через 4 часа
    /// после утреннего приёма»). Оба числа берутся из дневника:
    /// час — у действующей схемы, дата — у дела ухода.
    @ViewBuilder
    private var планКонтроля: some View {
        if let контроль = назначенныйКонтроль, let дата = контроль.scheduledDate {
            TGCard {
                TGSectionHeader(title: "когда сдавать")
                Text(.готовая(контроль.title))
                    .textStyle(AppFont.bodyEmphasis)
                    .wraps()
                Text(.готовая(строкаПлана(дата)))
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .wraps()
            }
        }
    }

    /// «7 декабря · через 40 дней. Таблетка в 09:30, кровь около 13:30.»
    ///
    /// Если часов схемы нет — вторая половина не печатается вовсе.
    /// Выдуманный час забора в медицинской записи хуже отсутствующего:
    /// по нему поедут в клинику.
    private func строкаПлана(_ дата: Date) -> String {
        let дней = Calendar.current.dateComponents([.day], from: Date(), to: дата).day ?? 0
        var строка = String(localized: "\(Fmt.shortDay(дата)) · через \(дней) дней")
        if let утро = утренняяДоза {
            let таблетка = Fmt.clock(minuteOfDay: утро)
            let кровь = Fmt.clock(minuteOfDay: утро + 4 * 60)
            строка += " " + String(localized: "Таблетка в \(таблетка), кровь около \(кровь).")
        }
        return строка
    }

    /// Отметки забора крови после дозы — то, чем закрываются точки
    /// протокола.
    ///
    /// # Почему сравнение по тексту, и где у него граница
    ///
    /// Забор записывается как `LogKind.note` с текстом «Забор крови»
    /// (`recordDraw` ниже). Отдельного поля у него нет, и завести
    /// его — это менять форму схемы, то есть отдельное решение.
    ///
    /// Сравнивается И с текущим переводом, И с русским ключом: запись,
    /// сделанная до смены языка интерфейса, иначе перестала бы
    /// закрывать свою точку. Полного покрытия это не даёт — сменивший
    /// язык с французского на английский посреди протокола увидит
    /// точку открытой, — и граница названа здесь, а не обойдена
    /// молчанием.
    ///
    /// Порядок: первый забор закрывает +4, второй +6. Это проще
    /// сопоставления по времени и честнее: врач берёт кровь не минута
    /// в минуту, а окно вокруг плановой точки пришлось бы выдумывать.
    private func заборы(после givenAt: Date) -> [LogEvent] {
        let имя = String(localized: "Забор крови")
        return Diary.active(dog?.events ?? [])
            .filter { $0.kind == .note && $0.date >= givenAt }
            .filter { $0.note == имя || $0.note == "Забор крови" }
            .sorted { $0.date < $1.date }
    }

    private func recordDraw() {
        EventLog(context: context, appState: appState)
            .record(.note, dog: dog, confirmation: "Записано · забор крови") { event in
                // Через каталог: заметку человек читает в ленте дня
                // и в сводке врачу. `note` — `String`, присвоение
                // литерала каталог не спрашивает, и у француза
                // в собственном дневнике встало бы русское слово.
                event.note = String(localized: "Забор крови")
            }
    }
}

private struct ProtocolRow: View {
    let label: String
    let time: Date
    let title: String
    let detail: String
    let isDone: Bool
    /// Что делать по нажатию на кружок. `nil` — строка только
    /// показывает (как «T0 · доза»: её отметил приём препарата).
    var отметить: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s12) {
            Text(label)
                .textStyle(AppFont.numeric(15))
                .fixedSize()
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: Token.Space.s2) {
                Text("\(Fmt.clock(time)) · \(title)").textStyle(AppFont.bodyEmphasis)
                Text(detail).textStyle(AppFont.caption)
            }
            Spacer(minLength: Token.Space.s8)
            // КРУЖОК НАЖИМАЕТСЯ, если строке есть что отметить.
            //
            // **Прежде это была голая картинка**, и отзыв 27.10.2026
            // сказал ровно это: «Не отмечается». Человек видел кружок
            // против «забор крови», жал — и не происходило ничего.
            // Кнопка «Отметить забор крови» внизу экрана писала запись
            // в дневник, но на кружок не влияла никак.
            if let отметить {
                Button(action: отметить) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? Token.Action.doneText : Token.Ink.secondary)
                        .frame(minWidth: Token.Size.tapTarget,
                               minHeight: Token.Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDone)
                .accessibilityLabel(isDone ? "Забор отмечен" : "Отметить забор крови")
            } else {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Token.Action.doneText : Token.Ink.secondary)
            }
        }
        .padding(.vertical, Token.Space.s10)
    }
}
