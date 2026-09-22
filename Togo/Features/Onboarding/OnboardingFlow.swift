import SwiftUI
import SwiftData

/// Онбординг · 90 секунд, аккаунт не нужен.
/// Три шага и ни одного обязательного поля сверх клички и веса.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]

    @State private var step: Step = .welcome
    @State private var draft = DogDraft()
    @State private var schedule = ScheduleDraft()
    /// Собаку пропустили: создавать её на выходе нельзя.
    @State private var skippedDog = false

    /// Онбординг можно пройти заново из настроек. Тогда собака уже есть,
    /// и шаги, которые её создают, надо пропустить — иначе получится вторая.
    private var isReplay: Bool { !dogs.isEmpty }

    enum Step: Int, CaseIterable {
        case welcome, dog, schedule, care, family, notifications

        var index: Int { rawValue }
        var progress: String? { self == .welcome ? nil : "\(rawValue) из 5" }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:       WelcomeStep(isReplay: isReplay) { advance() }
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
                        CareStep(onNext: { advance() })
                    }
                case .family:
                    if isReplay {
                        HowItWorksReplayEnd(onDone: finish)
                    } else {
                        FamilyStep(onSkip: { advance() }, onInvite: { advance() })
                    }
                case .notifications: NotificationsPrimingStep(onDone: finish)
                }
            }
            .background(Token.Surface.screen)
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
        if step == .schedule, !isReplay, !skippedDog { saveDog() }
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
