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

    /// Онбординг можно пройти заново из настроек. Тогда собака уже есть,
    /// и шаги, которые её создают, надо пропустить — иначе получится вторая.
    ///
    /// В просмотре собака тоже есть, а подменять шаги нельзя: смотрят
    /// ровно их. Вместо подмены запись выключается ниже — `пишемВБазу`.
    private var isReplay: Bool { !dogs.isEmpty && !просмотр }

    /// Единственное место, где решается, трогать ли хранилище.
    ///
    /// Отдельным именем, а не третьим условием в `advance()`: запрет
    /// на запись — это предмет, а не частность перехода. Ошибись здесь,
    /// и просмотр заведёт человеку вторую собаку, то есть инструмент
    /// сверки испортит её данные.
    private var пишемВБазу: Bool { !isReplay && !skippedDog && !просмотр }

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
        if step == .schedule, пишемВБазу { saveDog() }
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
