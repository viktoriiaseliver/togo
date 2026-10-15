import SwiftUI
import SwiftData

/// Онбординг · 90 секунд, аккаунт не нужен.
/// Три шага и ни одного обязательного поля сверх клички и веса.
struct OnboardingFlow: View {
    /// Просмотр: показать настоящие шаги и ничего не записать.
    ///
    /// Отличается от повторного прохождения тем же, чем показ от установки:
    /// повтор — это чтение справки человеком, который уже всё настроил,
    /// просмотр — взгляд на то, что увидит новый. Сверять макет можно
    /// только со вторым.
    var просмотр: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]

    @State private var step: Step = .welcome
    @State private var draft = DogDraft()
    @State private var schedule = ScheduleDraft()
    /// Собаку пропустили: создавать её на выходе нельзя.
    @State private var skippedDog = false

    /// Открыта ветка «меня позвали в семью».
    ///
    /// Отдельным состоянием, а не шагом `Step`, и это не экономия:
    /// шаги считаются человеку строкой «N из 5», а ветка «позвали» —
    /// не шаг онбординга, а **выход из него**. Добавь её в `Step`,
    /// и у всех остальных сдвинется номер, то есть человек, заводящий
    /// собаку, увидит «1 из 6» ради дороги, по которой он не идёт.
    @State private var позвали = false

    /// Какой это поток. **Поле, а не вычисление, и это предмет.**
    ///
    /// Онбординг можно пройти заново из настроек. Тогда собака уже есть,
    /// и шаги, которые её создают, надо пропустить — иначе получится
    /// вторая. В просмотре собака тоже есть, а подменять шаги нельзя:
    /// смотрят ровно их, и вместо подмены выключается запись
    /// (`пишемВБазу`). Три разных случая, поэтому три случая
    /// перечисления, а не один флаг.
    ///
    /// Было: `isReplay = !dogs.isEmpty && !просмотр` — то есть режим
    /// потока вычислялся из базы, в которую этот же поток пишет.
    /// `saveDog()` на шаге `.schedule` вставлял собаку, `@Query dogs`
    /// перестаёт быть пустым, `isReplay` переворачивался **посреди
    /// первого прохода**, и `case .care` отдавал «Это всё» с `finish`.
    /// Три шага из шести — уход, семья, уведомления — были недостижимы
    /// по построению. Жило с `0653a4e` (26.08.2026 01:33) и уехало
    /// во всех двенадцати сборках.
    ///
    /// Два звена при этом прожили вместе час тридцать шесть безвредно:
    /// переворот происходил, но `.care` про `isReplay` не спрашивал —
    /// у перевёрнутого знака не было читателя. Поэтому `git log -S`
    /// называет не виновного, а всю эволюцию.
    enum Режим { case первыйПроход, повтор, просмотр }

    /// Ставится один раз при входе в поток и больше не меняется.
    @State private var режим: Режим?

    /// Пока не поставлен — считаем как раньше. Так первый кадр
    /// не отличается от нынешнего поведения, и у перечитывающего
    /// не мигает подпись кнопки на `.welcome`.
    private var режимСейчас: Режим {
        режим ?? (просмотр ? .просмотр : (dogs.isEmpty ? .первыйПроход : .повтор))
    }

    private var isReplay: Bool { режимСейчас == .повтор }

    /// Единственное место, где решается, трогать ли хранилище.
    ///
    /// Отдельным именем, а не третьим условием в `advance()`: запрет
    /// на запись — это предмет, а не частность перехода. Ошибись здесь,
    /// и просмотр заведёт человеку вторую собаку, то есть инструмент
    /// сверки испортит её данные.
    private var пишемВБазу: Bool { режимСейчас == .первыйПроход && !skippedDog }

    /// Собака уже записана этим проходом.
    ///
    /// **Отдельным флагом, а не следствием из `пишемВБазу`.** До правки
    /// от второй собаки защищал побочный эффект: после `saveDog()`
    /// база перестаёт быть пустой, `isReplay` становится истинным,
    /// `пишемВБазу` — ложным, и повторный проход через `.schedule`
    /// («Назад» на `.dog`, потом снова вперёд) второй раз не писал.
    /// Заморозка режима эту защиту снимает — и дубль родился бы молча,
    /// а дубль собаки это первая карточка на экране «Семья».
    ///
    /// То есть починка одного отказа делала тихим соседний. Поэтому
    /// запрет назван своим именем, а не унаследован.
    @State private var собакаСохранена = false

    enum Step: Int, CaseIterable {
        case welcome, dog, schedule, care, family, notifications

        var index: Int { rawValue }
        var progress: String? { self == .welcome ? nil : String(localized: "\(rawValue) из 5") }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:
                    WelcomeStep(isReplay: isReplay,
                                onNext: { advance() },
                                // Ветка «позвали» НЕ продвигает онбординг
                                // и ничего не пишет в базу: человек ещё
                                // не решил, он здесь или нет. Решает
                                // за него система, когда он откроет
                                // ссылку, — и тогда сработает делегат
                                // сцены, а не этот экран.
                                onJoin: { позвали = true })
                case .dog:
                    if isReplay {
                        // Собака уже есть — вместо формы показываем то,
                        // ради чего онбординг и перечитывают.
                        HowItWorksScreen()
                            .safeAreaInset(edge: .bottom) {
                                TGButton(title: "Дальше") { advance() }
                                    .padding(.horizontal, Token.Spacing.screenPadding)
                                    .padding(.bottom, Token.Space.s8)
                                    .background(.regularMaterial)
                            }
                    } else {
                        DogStep(draft: $draft, onNext: { advance() }, onSkip: { skipDog() })
                    }
                case .schedule:
                    if isReplay {
                        HowItWorksReplayEnd(onDone: finish)
                    } else {
                        ScheduleStep(draft: $schedule) { advance() }
                    }
                case .care:
                    if isReplay {
                        HowItWorksReplayEnd(onDone: finish)
                    } else {
                        CareStep(пишемВБазу: пишемВБазу, onNext: { advance() })
                    }
                case .family:
                    if isReplay {
                        HowItWorksReplayEnd(onDone: finish)
                    } else {
                        FamilyStep(пишемВБазу: пишемВБазу,
                                   onSkip: { advance() }, onInvite: { advance() })
                    }
                case .notifications:
                    // Здесь `!просмотр`, а НЕ общий `пишемВБазу`, и это
                    // не описка. `пишемВБазу` ложно и при «Пока без
                    // собаки» — а человек, пропустивший собаку, проходит
                    // настоящий онбординг, и разрешение на уведомления
                    // у него надо спросить по-настоящему. Не спросить
                    // значит отнять у него пуши молча.
                    NotificationsPrimingStep(пишемВБазу: !просмотр, onDone: finish)
                }
            }
            .background(Token.Surface.screen)
            // Лист, а не шаг: из ветки «позвали» человек возвращается
            // туда же, откуда пришёл, ничего не потеряв. Онбординг
            // под ним стоит на месте — он не пройден и не отменён.
            .sheet(isPresented: $позвали) {
                ПозвалиВСемью { позвали = false }
            }
            .toolbar {
                if let progress = step.progress, !isReplay {
                    ToolbarItem(placement: .principal) {
                        Text(progress).textStyle(AppFont.micro)
                    }
                }
                // Шаг назад есть везде, кроме первого экрана: человек должен
                // иметь право передумать, а не только идти вперёд.
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            back()
                        } label: {
                            Label("Назад", systemImage: "chevron.left")
                        }
                    }
                }
                // Выход есть и отсюда: перечитал — и вернулся к дневнику.
                if isReplay {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрыть") { finish() }
                    }
                }
            }
            // Режим ставится ОДИН раз, на входе в поток, и дальше
            // не пересчитывается. Без этой строки `режимСейчас` остаётся
            // прежним вычислением из базы — то есть дефект возвращается
            // целиком, молча и без красного теста.
            .task {
                if режим == nil {
                    режим = просмотр ? .просмотр
                        : (dogs.isEmpty ? .первыйПроход : .повтор)
                }
            }
            .usageScreen(.onboarding)
            // Где человек застревает в онбординге, видно только по шагам:
            // «дошёл до режима дня и вышел» — это претензия к шагу,
            // а не к приложению целиком.
            .onChange(of: step) { _, next in
                UsageLog.note(.open, String(describing: next), on: .onboarding)
            }
        }
    }

    /// Пропустить собаку.
    ///
    /// Два шага следом — режим дня и уход — настраивают именно её, поэтому
    /// пропускаются вместе с ней: спрашивать, во сколько ест собака,
    /// которой нет, бессмысленно. Человек попадает сразу к уведомлениям
    /// и дальше в приложение; завести собаку можно в любой момент
    /// («Настройки → Добавить собаку»).
    private func skipDog() {
        skippedDog = true
        UsageLog.note(.open, "dogSkipped", on: .onboarding)
        withAnimation(.easeInOut(duration: Token.Duration.quick)) {
            step = .notifications
        }
    }

    private func advance() {
        // Повторное прохождение ничего не создаёт: это чтение, а не установка.
        // Второе условие — про ЭТОТ проход, а не про режим: человек может
        // вернуться «Назад» на карточку собаки и пойти вперёд снова.
        if step == .schedule, пишемВБазу, !собакаСохранена {
            saveDog()
            собакаСохранена = true
        }
        withAnimation(.easeInOut(duration: Token.Duration.quick)) {
            step = Step(rawValue: step.rawValue + 1) ?? .notifications
        }
    }

    private func back() {
        withAnimation(.easeInOut(duration: Token.Duration.quick)) {
            step = Step(rawValue: step.rawValue - 1) ?? .welcome
        }
    }

    private func saveDog() {
        let dog = draft.makeDog()
        DogOrigin.заведенаЗдесь(dog.id)
        schedule.apply(to: dog)
        context.insert(dog)
        SeedData.attachStarterCare(to: dog, context: context)
        let me = FamilyMember(name: draft.ownerName, role: .owner, isMe: true)
        context.insert(me)
        // Своя карточка запоминается на телефоне: `isMe` уезжает в общий
        // дневник и на втором устройстве указывает не на того.
        appState.myMemberID = me.id
    }

    private func finish() {
        // Просмотр не «проходят» — из него выходят. Поставить здесь флаг
        // значило бы записать человеку прохождение онбординга за то,
        // что он посмотрел на него, а стенду — закрыть вторую партию
        // кадров: `просмотрОнбординга` гасится, и следующий запуск
        // в тот же онбординг уже не попадёт.
        guard !просмотр else {
            appState.просмотрОнбординга = false
            return
        }
        settings.onboardingCompleted = true
        settings.lastSeenVersion = settings.appVersion
    }
}

/// Черновик собаки живёт отдельно от модели: пока человек не дошёл до конца шага,
/// в базе ничего нет.
struct DogDraft {
    var name = ""
    var weight = ""
    var breed = ""
    var sex: DogSex = .unknown
    var isNeutered = false
    var birthDate: Date?
    var hasBirthDate = false
    var isOnTreatment = false
    var photo: Data?
    var ownerName = "Я"

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && weightValue != nil }

    var weightValue: Double? {
        Double(weight.replacingOccurrences(of: ",", with: "."))
    }

    /// Режим питания приезжает отдельным шагом — здесь только то,
    /// что человек ввёл на карточке собаки.
    func makeDog() -> Dog {
        let dog = Dog(name: name.trimmingCharacters(in: .whitespaces), weightKg: weightValue ?? 0)
        dog.breed = breed.isEmpty ? nil : breed
        dog.sex = sex
        dog.isNeutered = isNeutered
        dog.birthDate = hasBirthDate ? birthDate : nil
        dog.isOnTreatment = isOnTreatment
        dog.photo = photo
        return dog
    }
}

// MARK: - Шаг 1 · зачем это
