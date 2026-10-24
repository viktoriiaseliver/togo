import SwiftUI
import SwiftData

/// Итог занятия. Граммы нужны здесь — в итоге, а не во время работы.
struct SessionSummarySheet: View {
    let session: TrainingSession
    let step: TrainingStep?
    var onDone: () -> Void

    var body: some View {
        // Куски вынесены в переменные не для красоты: со склейкой прямо
        // в вызове компилятор не укладывается в отведённое ему время.
        let длительность = Fmt.duration(Double(session.durationSeconds))
        let подпись = session.cue + " · " + session.place + " · " + session.person
        return TGSheet(
            title: "Занятие · \(длительность)",
            subtitle: .готовая(подпись)
        ) {
            resultCard
            if !session.observations.isEmpty { observationsCard }
            nextStepCard
        } footer: {
            TGButton(title: "Сохранить", action: onDone)
        }
    }

    private var resultCard: some View {
        TGCard {
            if session.isVoided {
                TGBanner(tone: .waiting, title: "Оценку не ставим",
                         subtitle: "Он не брал еду — значит, задача была слишком сложной. Это не про собаку.",
                         systemImage: "hand.raised")
            } else {
                Text("\(session.successes) из \(session.attempts)").textStyle(AppFont.display)
                Text(verdictLine).textStyle(AppFont.caption)
            }
            TGDivider()
            HStack(spacing: 0) {
                TGStat(value: "\(session.onTimeMarks) из \(session.markDelaysMs.count)", caption: "маркер в момент")
                TGStat(value: "\(session.averageDelayMs) мс", caption: "средняя задержка")
                TGStat(value: "\(session.gramsUsed) г", caption: "ушло из порции")
            }
            TGExplainer(text: "Вечерняя порция уже уменьшена на \(session.gramsUsed) г — корм на занятия берётся из еды, а не сверх неё.")
        }
    }

    private var verdictLine: String {
        if !session.countsTowardProgress { return String(localized: "после трёх минут прогресс не пишем") }
        if session.isGoodSession { return String(localized: "получилось · шаг почти закрыт") }
        if session.isPoorSession { return String(localized: "тяжело — стоит вернуться на шаг назад") }
        return String(localized: "нормально · держим этот шаг")
    }

    private var observationsCard: some View {
        TGCard {
            TGSectionHeader(title: "что заметила")
            ForEach(Array(session.observations), id: \.self) { observation in
                HStack(spacing: Token.Space.s8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(observation.stopsSession ? Token.Status.overdueText : Token.Ink.secondary)
                    Text(observation.title).textStyle(AppFont.caption)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var nextStepCard: some View {
        TGCard {
            Text("Следующее занятие").textStyle(AppFont.cardTitle)
            Text(nextStepText).textStyle(AppFont.caption)
            TGDivider()
            Text("Если сорвалось").textStyle(AppFont.bodyEmphasis)
            Text("Два занятия хуже 3 из 5 — приложение само предложит вернуться на шаг назад. Это не откат прогресса, а нормальный ход обучения.")
                .textStyle(AppFont.caption)
        }
    }

    private var nextStepText: String {
        guard let step else { return String(localized: "Повтори то же самое ещё раз: одно удачное занятие — не навык.") }
        if step.isClosed {
            return String(localized: "Шаг закрыт. Меняй одно условие: место, человека или дистанцию — но только что-то одно за раз.")
        }
        return String(localized: "\(step.summary), ещё раз. Одно удачное занятие — не навык; нужно второе, чтобы идти дальше.")
    }
}

/// Перенос навыка. Навык переносится по трём осям, и каждую нужно проходить
/// отдельно: кто просит, где просят и что вокруг происходит.
struct TransferMatrixScreen: View {
    let dog: Dog?

    @Query private var steps: [TrainingStep]

    private var mySteps: [TrainingStep] {
        steps.filter { $0.dog?.persistentModelID == dog?.persistentModelID }
    }

    var body: some View {
        TGScreen {
            CinemaHeader("Перенос навыка", отступы: false)
            TGExplainer(text: "Навык не «выучен» или «не выучен». «Ко мне» дома и «ко мне» на улице рядом с другой собакой — два разных навыка.")

            axisCard(title: "где", values: places)
            axisCard(title: "кто просит", values: people)
            distanceCard

            // ВОРОТА СНЯТЫ 24.10.2026, решение Виктории: «убери обещание
            // и матрицу, это просто помощь». Перенос навыка открыт всем.
            //
            // Снято вместе с обещанием, а не вместо него: пейволл обещал
            // «Матрицу переноса навыка · кто просит × где просят × что
            // вокруг», то есть СЕТКУ навык × контекст (эталон v10,
            // `29-screens.jpg`), а здесь три отдельных списка — где,
            // кто просит, дистанция. Пересечений, ради которых матрица
            // и нужна, не было нигде, и платили за них.
            //
            // > **Снять ворота, не сняв обещание, было бы хуже обоих:**
            // > строка в пейволле продавала бы то, что стало бесплатным.
            // > Разбор — `Togo/Store/ProGate.swift`, решение —
            // > `Дизайн/РЕШЕНИЯ-ДИЗАЙНА.md`, где его прочтёт автор макета.
            nextStepCard
        }
        .navigationTitle("Перенос навыка")
        .cinemaScreen()
    }

    private var places: [(String, SkillStatus)] {
        Dictionary(grouping: mySteps, by: \.place)
            .map { ($0.key, $0.value.map(\.status).max(by: statusOrder) ?? .notStarted) }
            .sorted { $0.0 < $1.0 }
    }

    private var people: [(String, SkillStatus)] {
        Dictionary(grouping: mySteps, by: \.person)
            .map { ($0.key, $0.value.map(\.status).max(by: statusOrder) ?? .notStarted) }
            .sorted { $0.0 < $1.0 }
    }

    private func statusOrder(_ lhs: SkillStatus, _ rhs: SkillStatus) -> Bool {
        let order: [SkillStatus] = [.notStarted, .learning, .works]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    private func axisCard(title: String, values: [(String, SkillStatus)]) -> some View {
        TGCard {
            TGSectionHeader(title: .готовая(title))
            if values.isEmpty {
                TGExplainer(text: "Пока пусто. Ось заполнится сама, когда пройдёт первое занятие.")
            } else {
                ForEach(values, id: \.0) { name, status in
                    HStack {
                        Text(name).textStyle(AppFont.body)
                        Spacer(minLength: Token.Space.s8)
                        Text(status.title).textStyle(AppFont.caption.color(status.color))
                    }
                    .frame(minHeight: Token.Size.tapTarget)
                }
            }
        }
    }

    private var distanceCard: some View {
        TGCard {
            TGSectionHeader(title: "насколько далеко")
            let distances = Set(mySteps.map(\.distanceMeters)).sorted()
            HStack(spacing: Token.Space.s8) {
                ForEach(distances.isEmpty ? [2, 5, 10, 20] : distances, id: \.self) { meters in
                    Text("\(meters) м")
                        .textStyle(AppFont.captionEmphasis)
                        .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget)
                        .background(Token.Surface.sunken,
                                    in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                }
            }
        }
    }

    private var nextStepCard: some View {
        TGCard {
            Text("Следующий шаг — один").textStyle(AppFont.cardTitle)
            Text("Меняй за раз что-то одно: новое место — верни короткую дистанцию.")
                .textStyle(AppFont.caption)
        }
    }
}

/// Подготовка к процедурам. Приложение уже знает, что забор крови будет, —
/// значит, может предложить готовиться заранее, короткими подходами.
struct ProcedurePrepScreen: View {
    @Query private var skills: [ProcedureSkill]
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    /// Заготовки подставляются один раз.
    ///
    /// Раньше условием было «список пуст» — то есть удалить навык было
    /// нельзя даже теоретически: он возвращался при следующем заходе.
    @AppStorage("procedureSkills.seeded") private var seeded = false

    @State private var removing: ProcedureSkill?
    /// Навык, по которому записываем попытку.
    @State private var открыт: ProcedureSkill?

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            CinemaHeader("Процедуры", отступы: false)
            TGExplainer(text: "Самое ценное обучение для собаки с регулярными процедурами — не «место», а спокойно дать лапу, стоять при осмотре и самой залезать в переноску.")

            if skills.isEmpty {
                EmptyStateCard(
                    subject: .training,
                    title: "Список пуст",
                    message: "Навыки для процедур убраны. Заготовки можно вернуть — это три самых нужных: дать лапу, стоять при осмотре и залезть в переноску.",
                    actionTitle: canEdit ? "Вернуть заготовки" : nil,
                    action: canEdit ? { seed() } : nil
                )
            }

            ForEach(skills) { skill in
                // Нажатие открывает запись попытки, а не удаление.
                //
                // До 28.09 тап по строке предлагал УБРАТЬ навык — то есть
                // единственным действием экрана было разрушительное,
                // и оно же было самым лёгким. Удаление переехало внутрь
                // листа, где стоит отдельной кнопкой.
                Button { if canEdit { открыт = skill } } label: {
                    TGCard {
                        HStack {
                            VStack(alignment: .leading, spacing: Token.Space.s2) {
                                Text(skill.title).textStyle(AppFont.bodyEmphasis)
                                Text(skill.detail).textStyle(AppFont.caption).wraps()
                            }
                            Spacer(minLength: Token.Space.s8)
                            Text(skill.status.title).textStyle(AppFont.caption.color(skill.status.color))
                        }
                        // Строка счёта стояла под `attempts > 0`, и это
                        // условие не бывало истинным никогда: попытки
                        // не записывал никто. Теперь записывает — но
                        // при нуле попыток честнее сказать, чего ждём,
                        // чем не сказать ничего.
                        if skill.attempts > 0 {
                            Text("\(skill.successes) из \(skill.attempts)")
                                .textStyle(AppFont.numeric(17))
                            let осталось = SkillProgress.attemptsUntilVerdict(attempts: skill.attempts)
                            if осталось > 0 {
                                Text("ещё \(осталось) попыток — и будет видно, получается ли")
                                    .textStyle(AppFont.micro)
                                    .wraps()
                            }
                        } else {
                            Text("попыток пока нет")
                                .textStyle(AppFont.micro)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
            }

            TGCard {
                Text("Правило одно").textStyle(AppFont.cardTitle)
                Text("Собака в любой момент может уйти. Ушла — значит, задача была слишком сложной, а не собака плохая. Держать силой нельзя: один такой раз откатывает недели работы.")
                    .textStyle(AppFont.caption)
            }
        }
        .navigationTitle("Процедуры")
        .cinemaScreen()
        .task { seedOnce() }
        .sheet(item: $открыт) { skill in
            SkillAttemptSheet(skill: skill) { удалить in
                открыт = nil
                if удалить { removing = skill }
            }
        }
        .confirmationDialog("Убрать навык?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible,
                            presenting: removing) { skill in
            Button("Убрать", role: .destructive) { delete(skill) }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: { skill in
            Text("«\(skill.title)» пропадёт вместе с накопленными попытками. Заготовки можно вернуть, когда список опустеет.")
        }
    }

    private func seedOnce() {
        guard !seeded, skills.isEmpty else { return }
        seed()
    }

    private func seed() {
        let заведённые = SeedData.procedureSkills()
        заведённые.forEach(context.insert)
        // Не сохранилось — не помечаем засеянным: иначе список пуст,
        // а приложение считает, что уже всё завело.
        seeded = context.persist(otherwise: { заведённые.forEach(context.delete) })
    }

    private func delete(_ skill: ProcedureSkill) {
        context.delete(skill)
        guard context.persist(otherwise: {}) else {
            Haptics.warning()
            return
        }
        Haptics.warning()
        removing = nil
    }
}
