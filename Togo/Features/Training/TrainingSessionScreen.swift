import SwiftUI
import SwiftData

/// Занятие. Приложение здесь — секундомер и зеркало, а не счётчик корма.
struct TrainingSessionScreen: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var steps: [TrainingStep]

    @State private var session: MarkerSession
    @State private var now = Date()
    @State private var summary: TrainingSession?
    @State private var isConfirmingExit = false

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(dog: Dog?) {
        self.dog = dog
        _session = State(initialValue: MarkerSession(limitMinutes: dog?.sessionLengthMinutes ?? 3))
    }

    private var mySteps: [TrainingStep] {
        steps.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
            .sorted { $0.order < $1.order }
    }

    private var currentStep: TrainingStep? {
        mySteps.first { !$0.isClosed } ?? mySteps.first
    }

    /// Первый шаг заводится сам при первом занятии.
    ///
    /// Раньше шаги не создавал никто: занятие всегда шло «без шага»,
    /// прогресс не двигался, а матрица переноса оставалась пустой навсегда.
    /// Начинаем с самого лёгкого — дома, два метра: с этого и начинают.
    private func ensureFirstStep() {
        guard let dog, mySteps.isEmpty else { return }
        let step = TrainingStep(cue: "Ко мне", place: "Дома",
                                person: appState.currentUserName,
                                distanceMeters: 2, order: 0)
        step.status = .learning
        step.dog = dog
        context.insert(step)
        if !context.persist(otherwise: { context.delete(step) }) {
            Haptics.warning()
            appState.showFailure("Шаг не завёлся · попробуй ещё раз")
        }
    }

    var body: some View {
        Group {
            if let summary {
                SessionSummarySheet(session: summary, step: currentStep) { dismiss() }
            } else {
                sessionSheet
            }
        }
        .presentationDetents([.large])
        .usageScreen(.training)
        .task { ensureFirstStep() }
        .onReceive(tick) { now = $0 }
        .confirmationDialog("Занятие не сохранится", isPresented: $isConfirmingExit, titleVisibility: .visible) {
            Button("Сохранить и выйти") { finish() }
            Button("Выйти без записи", role: .destructive) { dismiss() }
            Button("Вернуться к занятию", role: .cancel) {}
        } message: {
            Text("Отметок уже \(session.delaysMs.count). Их можно записать — прогресс посчитается, если занятие уложилось в три минуты.")
        }
    }

    private var sessionSheet: some View {
        TGSheet(
            title: session.isRunning ? "Занятие идёт" : "Точность маркера",
            subtitle: currentStep.map { .готовая($0.fullSummary) }
                ?? "поставь руку один раз — потом маркер уйдёт на кнопку громкости",
            closeTitle: session.isRunning ? "Прервать занятие" : "Закрыть",
            // Молча терять отметки нельзя: занятие уже прошло, даже если
            // человек передумал его сохранять.
            onClose: session.isRunning && !session.delaysMs.isEmpty
                ? { isConfirmingExit = true }
                : nil
        ) {
            // **Маркер первым, часы вторыми — порядок с эталона v10,
            // `27-screens.jpg`.** На кадре белая карточка маркера стоит
            // над всем остальным, а числа занятия («Идёт», «Успехов»,
            // «Лакомство») лежат под ней списком. Прежний порядок ставил
            // первыми часы: самое нажимаемое на экране оказывалось
            // за крупным секундомером, который не нажимают ни разу.
            markerPad
            clock
            recentMarks
            markerKindRow
            observations
        } footer: {
            if session.isRunning {
                // **Белая, а не шалфейная — замер, а не вкус.**
                // `.finish` это `Button.Finish.background` =
                // `arcticTint` = `#FFFFFF2E`, то есть белый под α .18:
                // на чёрном «Кино» он читается тусклой серой плашкой.
                // На эталоне v10 (`27-screens.jpg`) кнопка завершения
                // занятия **белая сплошная**, как `Button.Primary`
                // (`arctic` = `#FFFFFF`). Правило «кирпич один на экран»
                // не нарушено: пока занятие идёт, других `.primary`
                // в этом подвале нет — рядом только `.quiet`.
                TGButton(title: "Закончить на удаче", variant: .primary,
                     systemImage: "checkmark") { finish() }
                TGButton(title: "Сбросить отметки", variant: .quiet, size: .medium) { session.reset() }
            } else {
                TGButton(title: "Начать занятие · \(Fmt.minutes(dog?.sessionLengthMinutes ?? 3))", systemImage: "play.fill") {
                    session.start()
                    Haptics.tap()
                }
            }
        }
    }

    // MARK: Часы

    private var clock: some View {
        TGCard {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.stopwatch(session.elapsed(at: now))).textStyle(AppFont.display)
                Spacer()
                if let accuracy = session.lastAccuracy, let ms = session.lastDelayMs {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(accuracy.title).textStyle(AppFont.cardTitle.color(accuracy.color))
                        Text("\(ms) мс").textStyle(AppFont.numeric(15).color(Token.Ink.secondary))
                    }
                }
            }
            ProgressView(value: min(1, session.elapsed(at: now) / Double(session.limitSeconds)))
                .tint(session.isOvertime(at: now) ? Token.Status.overdueText : Token.Status.doneText)
            Text(session.hint(at: now)).textStyle(AppFont.caption)

            if session.isOvertime(at: now) {
                TGBanner(tone: .alarm, title: "Три минуты прошли",
                         subtitle: "Дальше прогресс не пишем: после трёх минут собака угадывает, а не учится.",
                         systemImage: "hourglass")
            }
        }
    }

    // MARK: Два тапа — вся точность

    /// Маркер: белая карточка во всю ширину, первой на экране.
    ///
    /// # Почему это вообще правка, а не вкусовщина
    ///
    /// Эталон v10, `27-screens.jpg`: маркер — **белая карточка первым
    /// элементом во всю ширину**, подпись «жми, когда сделал». У нас он
    /// был третьей плиткой среди равных по 72–92 pt, и ранг нёс только
    /// цвет, который появляется на полсекунды. А нажимают из всего
    /// экрана именно его: маркер работает, если попасть в полсекунды
    /// после действия собаки, и **искать его глазами значит
    /// промахнуться** — промах тут не косметика, он портит ту самую
    /// величину, ради которой занятие и идёт.
    ///
    /// # Заливку и подпись выбирает ОДИН тип, и это не новый код
    ///
    /// `MarkFill` заведён ровно под эту развилку у прогулки
    /// (`MarkFill.swift`), и взят он здесь не ради переиспользования,
    /// а потому что прежний код наступил на то, от чего `MarkFill`
    /// и защищает:
    ///
    /// ```
    /// было  .background(isWaitingForMark ? Action.primary : …)
    ///       Text("Клик").textStyle(AppFont.cardTitle)
    /// ```
    ///
    /// `AppFont.cardTitle` несёт свой `color` (`Token.Ink.primary`),
    /// `textStyle` красит сам `Text` и побеждает `foregroundStyle`
    /// предка — то есть в состоянии ОЖИДАНИЯ МАРКЕРА, единственном,
    /// где эту кнопку читают, светлая подпись ложилась на белую
    /// заливку. Заливку меняли, подпись — нет. Цвет здесь подставлен
    /// ВМЕСТО стилевого (`textStyle(_:color:)`), а не поверх.
    ///
    /// # Почему карточка НЕ белая постоянно, хотя на кадре она белая
    ///
    /// `MarkerEngine.markMarker()` начинается с
    /// `guard let actionAt else { return nil }` — без первого тапа
    /// («Он сделал») маркер **не делает ничего и не может**: измеряется
    /// промежуток между двумя тапами, и мерить не от чего. Белая
    /// карточка, которая выглядит главным действием и молчит
    /// на нажатие, была бы хуже тусклой: это наш класс «молчаливый
    /// путь», только с приглашением.
    ///
    /// > Прототип рисует ОДИН тап, у нас их два, и это не исполнение,
    /// > а устройство: вся точность живёт в промежутке. Сведение двух
    /// > тапов в один — решение Виктории, не исполнителя; расхождение
    /// > названо здесь и в отчёте, а не замазано цветом.
    private var маркер: some View {
        let заливка: MarkFill = session.isWaitingForMark ? .accent : .quiet
        return Button { mark() } label: {
            HStack(spacing: Token.Space.s12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: Token.Size.iconLg, weight: Token.FontWeight.medium))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(dog?.markerKind.title ?? String(localized: "маркер"))
                        .textStyle(AppFont.cardTitle, color: заливка.label)
                        .wraps()
                    Text("жми, когда сделал")
                        .textStyle(AppFont.caption, color: заливка.counter)
                        .wraps()
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(заливка.label)
            .padding(.horizontal, Token.Space.s16)
            .padding(.vertical, Token.Space.s8)
            .frame(maxWidth: .infinity, minHeight: Token.Size.capsule, alignment: .leading)
            .background(заливка.color,
                        in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!session.isWaitingForMark)
    }

    private var markerPad: some View {
        VStack(spacing: Token.Space.s10) {
            маркер

            Button { session.markAction(); Haptics.tap() } label: {
                VStack(spacing: Token.Space.s2) {
                    Text("Он сделал").textStyle(AppFont.cardTitle)
                    Text("сел, посмотрел, подошёл").textStyle(AppFont.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(Token.Surface.sunken,
                            in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRunning || session.isWaitingForMark)

            // Третий исход занятия — и он обязан выглядеть нажимаемым.
            //
            // Здесь стоял голый `Button("Не получилось")` с
            // `.textStyle(AppFont.caption)`, и на кадре
            // `Дизайн/кадры-приёмки/витрина-редизайн-23.10/04-training.png`
            // он выходил подписью по центру: плашки нет, нажимаемым
            // не выглядит, рядом с двумя плитками читается как заголовок
            // следующей секции.
            //
            // Хуже видимого: `.textStyle` красит сам `Text` и побеждает
            // то, чем система гасит выключённое, — поэтому выключенная
            // кнопка рисовалась ЯРЧЕ двух соседних плиток, которые в тот
            // же момент честно потускнели. Замер по тому же кадру,
            // занятие не начато, то есть все три исхода выключены:
            //
            // ```
            // «Он сделал»     заголовок #8B8B8B  подпись #6F6F72   ← погасло
            // «Клик»          заголовок #8B8B8B  подпись #6F6F72   ← погасло
            // «Не получилось» подпись   #C7C7CC                    ← НЕ погасло
            // ```
            //
            // `TGButton` даёт плашку и уводит выключенное состояние
            // в `TGButtonStyle` через `isEnabled`. Те же слова и тот же
            // вариант уже стоят на втором исходе процедуры —
            // `SkillAttemptSheet.swift:45`.
            //
            // **И ровно половину он при этом не закрывает — в тёмной.**
            // Замер по двум кадрам, снятым в один прогон:
            //
            // ```
            //                плашка     подпись
            // включено       #3A3A3C    #FFFFFF   11,35:1   (04b-…-идёт)
            // выключено      #3A3A3C    #C7C7CC    6,74:1   (04-training)
            // ```
            //
            // Заливка в обоих состояниях ОДНА И ТА ЖЕ, байт в байт:
            // `Secondary.background` это `night4`, `Disabled.background`
            // это `night5`, и 23.10 оба стали `#3A3A3C`. Это известное
            // столкновение с хозяином — `ВыключеннаяИВторостепеннаяTests`,
            // вопрос «куда уводим выключенную кнопку» Виктории не задан.
            // Значит выключенное здесь различается ТОЛЬКО подписью,
            // и это лучше прежнего (там не различалось ничем), но не
            // «обе половины».
            //
            // Второе число оттуда же и тоже не закрыто: плашка третьего
            // исхода к плашке первого — **1,23:1** (`#3A3A3C` против
            // `#2C2C2E`). Заливкой ранг не читается; его несут высота
            // (50 против 72 и 92) и подпись. Поднимать ранг цветом —
            // решение дизайна, не исполнителя.
            //
            // Эталонного кадра у этого экрана нет: в
            // `Дизайн/эталонные-кадры/ios28-кино-22.10/` восемнадцать
            // кадров, и занятия среди них нет ни одного. Значит
            // решением дизайна прежний вид не был — его просто никто
            // не сверял.
            TGButton(title: "Не получилось", variant: .secondary, size: .medium,
                     systemImage: "xmark", isEnabled: session.isRunning) {
                session.markMiss()
            }
        }
    }

    private func mark() {
        session.markMarker()
        Haptics.marker()
    }

    // MARK: Последние отметки

    /// Лента задержек — и то, что стоит на её месте, пока отметок нет.
    ///
    /// **Пустое место — не пустое состояние.** Полоски лежали в `HStack`
    /// с жёстким `.frame(height: 48)`, и при нуле отметок этот `HStack`
    /// оставался пустым, а высоту держал. Замер по кадру
    /// `Дизайн/кадры-приёмки/витрина-редизайн-23.10/04-training.png`,
    /// по строкам без единого пикселя ярче `#464646` внутри карточки:
    ///
    /// ```
    /// дыра между «0 из 0 в момент» и «Ниже — быстрее…»
    ///   y 1739…1978 = 239 px при 3× = 79,7 pt    ← ничего не нарисовано
    /// ```
    ///
    /// Заодно уходят две величины, которые при нуле отметок ничего
    /// не измеряют: «среднее 0 мс» и «0 из 0 в момент». Ноль, посчитанный
    /// из пустого списка, выглядит как результат занятия.
    ///
    /// Образец пустого состояния — свой, не придуманный: «Пока не с чем
    /// сравнивать» на кадре `08-feeding.png` (`Feeding.swift:31`) —
    /// заголовок плюс объяснение, без шапки секции.
    private var recentMarks: some View {
        TGCard {
            if session.delaysMs.isEmpty {
                Text("Отметок пока нет")
                    .textStyle(AppFont.cardTitle)
                    .wraps()
                // **Цитата снята вместе с кнопкой, которую она цитировала.**
                // Кнопка больше не подписана «Клик»: на ней стоит сам
                // маркер — «кликер», «слово „да“» или «щелчок языком»,
                // то есть подпись меняется от настройки собаки. Цитировать
                // можно только НЕИЗМЕННУЮ подпись; здесь её нет, значит
                // верной цитаты не существует, и кнопка названа ролью.
                // Тот же дефект и то же лечение, что у пейволла сегодня же.
                TGExplainer(text: "Первая полоска появится, когда нажмёшь маркер. Ниже — быстрее: до полусекунды собака связывает маркер со своим действием, после секунды она уже делает что-то другое.")
            } else {
                HStack {
                    TGSectionHeader(title: "последние отметки")
                    Spacer()
                    Text("среднее \(session.averageDelayMs) мс").textStyle(AppFont.micro)
                }
                Text("\(session.onTimeCount) из \(session.delaysMs.count) в момент")
                    .textStyle(AppFont.numeric(20))
                HStack(spacing: Token.Space.s4) {
                    ForEach(Array(session.delaysMs.suffix(12).enumerated()), id: \.offset) { _, ms in
                        Capsule()
                            .fill(MarkAccuracy.from(delayMilliseconds: ms).color)
                            .frame(height: CGFloat(min(48, max(6, ms / 25))))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 48, alignment: .bottom)
                TGExplainer(text: "Ниже — быстрее. До полусекунды собака связывает маркер со своим действием. После секунды она уже делает что-то другое — и отмечаешь ты именно это.")
            }
        }
    }

    // MARK: Чем маркируешь

    private var markerKindRow: some View {
        TGCard {
            TGSectionHeader(title: "чем маркируешь")
            TGChipGroup(
                items: MarkerKind.allCases,
                title: \.title,
                isSelected: { dog?.markerKind == $0 }
            ) { kind in
                dog?.markerKind = kind
                Haptics.tap()
            }
            TGExplainer(text: "Маркер один и тот же всегда и больше ничего не значит. «Молодец» не годится: его говорят весь день.")
        }
    }

    // MARK: Что заметила

    private var observations: some View {
        TGCard {
            TGSectionHeader(title: "что заметила", subtitle: "это про условия, а не про собаку")
            TGChipGroup(
                items: SessionObservation.allCases,
                title: \.title,
                isSelected: { session.observations.contains($0) },
                tone: { $0.stopsSession ? .alarm : .neutral }
            ) { observation in
                toggle(observation)
            }
            if session.observations.contains(.refusedFood) {
                TGBanner(tone: .alarm, title: "Если не берёт еду — заканчивай",
                         subtitle: "Отказ от корма, за который он обычно работает, значит, что сейчас он учиться не может. Это не упрямство. Вернись к задаче попроще завтра.",
                         systemImage: "hand.raised")
            }
        }
    }

    private func toggle(_ observation: SessionObservation) {
        if session.observations.contains(observation) {
            session.observations.remove(observation)
        } else {
            session.observations.insert(observation)
        }
        Haptics.tap()
    }

    /// Шаг закрыт — открываем следующий, изменив **одно** условие.
    /// Сначала растёт дистанция, и только потом меняется место: менять
    /// два условия разом значит не понять, что именно не сработало.
    private func openNextStep(after step: TrainingStep, for dog: Dog) {
        let дистанции = [2, 5, 10, 20]
        let места = ["Дома", "Коридор", "Двор", "Улица без собак", "Парк, есть собаки"]

        let next: TrainingStep
        if let дальше = дистанции.first(where: { $0 > step.distanceMeters }) {
            next = TrainingStep(cue: step.cue, place: step.place, person: step.person,
                                distanceMeters: дальше, order: step.order + 1)
        } else if let индекс = места.firstIndex(of: step.place), индекс + 1 < места.count {
            // Новое место — возвращаем короткую дистанцию.
            next = TrainingStep(cue: step.cue, place: места[индекс + 1], person: step.person,
                                distanceMeters: дистанции[0], order: step.order + 1)
        } else {
            return
        }

        next.status = .notStarted
        next.dog = dog
        context.insert(next)
        if !context.persist(otherwise: { context.delete(next) }) {
            Haptics.warning()
            appState.showFailure("Следующий шаг не завёлся · попробуй ещё раз")
        }
    }

    // MARK: Итог

    private func finish() {
        guard let dog else { return }
        let record = TrainingSession(
            cue: currentStep?.cue ?? "Занятие",
            place: currentStep?.place ?? "дома",
            person: appState.currentUserName,
            distanceMeters: currentStep?.distanceMeters ?? 2
        )
        record.durationSeconds = Int(session.elapsed(at: now))
        record.markDelaysMs = session.delaysMs
        record.successes = session.successes
        record.attempts = max(session.attempts, session.delaysMs.count)
        record.gramsUsed = session.gramsUsed()
        record.observations = session.observations
        record.countsTowardProgress = session.countsTowardProgress(at: now)
        record.dog = dog
        context.insert(record)

        // Шаг закрыт при 4 из 5 в двух занятиях подряд; два плохих подряд —
        // предложение вернуться на шаг назад.
        if let step = currentStep, record.countsTowardProgress {
            if record.isGoodSession {
                step.consecutiveGoodSessions += 1
                step.status = step.isClosed ? .works : .learning
                if step.isClosed { openNextStep(after: step, for: dog) }
            } else if record.isPoorSession {
                step.consecutiveGoodSessions = 0
            }
        }

        // Через `EventLog` — там право, сторож дубля и ответ человеку,
        // если сохранить не вышло. Прежде этот путь шёл мимо всех трёх.
        EventLog(context: context, appState: appState)
            .record(.training, dog: dog, confirmation: nil) {
                $0.grams = record.gramsUsed
                $0.note = record.cue
                $0.trainingSessionID = record.id
            }

        summary = record
    }
}
