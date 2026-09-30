import SwiftUI
import SwiftData
import CloudKit

/// Данные и приватность. Выгрузить всё и удалить всё — два действия,
/// оба без писем и ожидания.
///
/// Тексты здесь обязаны совпадать с тем, как устроено хранилище:
/// база на телефоне зеркалится в личный iCloud (`Persistence.openContainer`,
/// `cloudKitDatabase: .private`), а общий дневник — это зона `family`,
/// которой владелец делится через `CKShare`. Прежняя шапка «Всё лежит
/// на телефоне» была неправдой с тех пор, как появилось зеркало.
struct DataPrivacyScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.familySync) private var sync
    @Query private var dogs: [Dog]
    @Query private var events: [LogEvent]

    @State private var isConfirmingDelete = false
    @State private var deleted = false
    /// Мы владелец общего дневника и приглашение существует: удаление
    /// всего его закроет, и об этом надо сказать до кнопки, а не после.
    @State private var ownsShare = false
    /// Стирание не прошло — причина для плашки.
    @State private var eraseFailure: String?
    /// Дневник на телефоне стёрт, а приглашение закрыть не удалось.
    @State private var shareFailure: String?

    /// Мы в чужом дневнике. Читается при показе, а не держится
    /// в состоянии: удаление его сбрасывает.
    private var isGuest: Bool { SharedDiarySettings.isOn && SharedZoneOwner.isGuest }

    private var activeEvents: [LogEvent] { Diary.active(events) }

    var body: some View {
        TGScreen {
            TGCard {
                Text("Где лежит дневник").textStyle(AppFont.cardTitle)
                Text("На этом телефоне и в твоём iCloud, если он включён. Если ведёшь дневник вдвоём — ещё и у приглашённого: на его телефоне и в его iCloud. Своих серверов, аккаунта и аналитики у нас нет.")
                    .textStyle(AppFont.caption)
                TGDivider()
                HStack(spacing: 0) {
                    TGStat(value: "\(activeEvents.count)", caption: "записей")
                    TGStat(value: "\(dogs.count)", caption: "собак")
                    TGStat(value: "\(Diary.daysOfData(activeEvents))", caption: "дней")
                }
            }

            if !appState.can(.exportData) {
                TGBanner(tone: .waiting, title: "Выгрузка недоступна",
                         subtitle: "Право «Выгружать данные и отчёты» выдаёт владелец в разделе «Семья».",
                         systemImage: "lock")
            }

            TGCard {
                TGSectionHeader(title: "выгрузить")
                ShareLink(
                    item: CSVFile(name: "togo-dnevnik.csv", text: Exporter.csv(events: activeEvents)),
                    preview: SharePreview("Дневник Togo · CSV")
                ) {
                    TGListRow(title: "Весь дневник · CSV", systemImage: "square.and.arrow.up")
                }
                TGDivider()
                ShareLink(
                    item: CSVFile(name: "togo-stul-vrachu.csv", text: Exporter.clinicalCSV(events: activeEvents)),
                    preview: SharePreview("Стул для врача · CSV")
                ) {
                    TGListRow(title: "Стул для врача · CSV", systemImage: "cross.case")
                }
                TGExplainer(text: "CSV открывается в Numbers и Excel. Бристольская шкала есть только здесь — в интерфейсе её цифр нет.")
            }
            .disabled(!appState.can(.exportData))

            TGCard {
                TGSectionHeader(title: "удалить")
                TGButton(title: "Удалить все данные", variant: .destructive, size: .medium, systemImage: "trash") {
                    isConfirmingDelete = true
                }
                TGExplainer(text: "Стирает записи, собак, схемы лечения и семью на этом телефоне и выключает здесь общий дневник. Отменить будет нельзя — сначала сохрани дневник в файл в «Перенос и восстановление», если может пригодиться.")
                TGExplainer(text: "Копию в своём iCloud можно стереть целиком в настройках iOS: iCloud → Управление хранилищем → Togo.")
            }

            if let eraseFailure {
                TGBanner(tone: .alarm, title: "Не получилось удалить",
                         subtitle: "Записи остались на телефоне. Причина: \(eraseFailure)",
                         systemImage: "exclamationmark.triangle")
            }

            if deleted {
                TGBanner(tone: .done, title: "Всё удалено",
                         subtitle: "На устройстве не осталось ни одной записи.",
                         systemImage: "checkmark.seal")
            }

            if let shareFailure {
                TGBanner(tone: .alarm, title: "Общий дневник не закрылся",
                         subtitle: "Приглашённые пока получают записи. Закрой его вручную: «Семья» → «Общий дневник» → «Перестать делиться». Причина: \(shareFailure)",
                         systemImage: "person.2.slash")
            }
        }
        .navigationTitle("Данные")
        .usageScreen(.dataPrivacy)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Удалить все данные?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { deleteEverything() }
            Button("Отмена", role: .cancel) {}
        } message: {
            if ownsShare {
                Text("Записи, собаки, схемы лечения и семья будут стёрты с этого телефона. Общий дневник закроется: приглашённые перестанут получать новые записи, а то, что уже получили, останется у них.")
            } else if isGuest {
                Text("Записи, собаки, схемы лечения и семья будут стёрты с этого телефона, общий дневник здесь выключится. У владельца он останется вместе с твоими прошлыми отметками — убрать тебя из участников может он.")
            } else {
                Text("Записи, собаки, схемы лечения и семья будут стёрты с этого телефона.")
            }
        }
        // Только читает: `existing` ничего не создаёт в облаке.
        .task { ownsShare = await FamilyShare.existing() != nil }
    }

    private func deleteEverything() {
        // Общий дневник — первым. Пока обмен идёт, он принёс бы чужие
        // записи и профиль собаки обратно в только что стёртую базу.
        // Слепок движка сбрасывается, чтобы включённый заново обмен
        // забрал общий дневник целиком, а не с места, где остановился.
        sync?.stop()
        SharedDiarySettings.isOn = false
        SyncStateStore.reset()
        SharedZoneOwner.reset()

        // Список моделей берётся из схемы (`BackupService.deletionOrder`):
        // здесь был свой список руками, и каскад от собаки при пачечном
        // удалении не срабатывает — без полного списка фото паспорта
        // и дни с собакой оставались на телефоне. Прежде здесь же стоял
        // `try?`: экран говорил «Всё удалено» при любом исходе.
        do {
            try BackupService.eraseEverything(in: context)
            try context.save()
        } catch {
            eraseFailure = error.localizedDescription
            deleted = false
            UsageLog.note(.delete, "erase-all", on: .dataPrivacy, outcome: .failed)
            return
        }
        eraseFailure = nil
        NotificationCenterService.cancelAll()
        deleted = true
        Haptics.warning()
        UsageLog.note(.delete, "erase-all", on: .dataPrivacy)

        // Приглашение закрывается той же операцией, что «Перестать делиться»
        // на экране общего дневника. Зона `family` с записями в iCloud
        // владельца при этом остаётся — удалять её приложение пока не умеет.
        if ownsShare { Task { await closeShare() } }
    }

    private func closeShare() async {
        do {
            try await FamilyShare.stopSharing()
            ownsShare = false
            shareFailure = nil
        } catch {
            shareFailure = error.localizedDescription
            UsageLog.note(.delete, "stop-share:\(FamilyShare.причина(error))",
                          on: .dataPrivacy, outcome: .failed)
        }
    }
}

struct SupportScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(\.openURL) private var openURL

    /// Что сказать, когда письмо открыть нечем.
    ///
    /// Отзыв: «Так же не работает ссылка. Аллерт». `mailto:` на телефоне
    /// без настроенной почты не открывается ничем, и человек видит
    /// системный алерт «Нет учётной записи» — приложение при этом молчит,
    /// потому что `openURL` без обработчика не знает, открылось ли.
    /// Тупик: адрес написан внутри ссылки, которую нельзя открыть.
    @State private var копияАдреса: String?

    private var diagnostics: String {
        """
        Togo \(settings.appVersion) (\(settings.buildNumber))
        iOS \(UIDevice.current.systemVersion)
        Устройство: \(UIDevice.current.model)
        """
    }

    var body: some View {
        TGScreen {
            TGCard {
                Text("Отвечает человек").textStyle(AppFont.cardTitle)
                Text("Обычно в течение двух рабочих дней. Если что-то в приложении мешает ухаживать за собакой — пиши сразу, это важнее фич.")
                    .textStyle(AppFont.caption)
                TGButton(title: "Написать в поддержку", size: .medium, systemImage: "envelope") {
                    openMail()
                }
                if let копияАдреса {
                    TGBanner(tone: .alarm, title: "Почта на телефоне не настроена",
                             subtitle: .готовая("Адрес скопирован: \(копияАдреса). Напиши с любого другого устройства — и приложи три строки ниже."),
                             systemImage: "envelope.badge.shield.half.filled")
                }
            }

            TGCard {
                TGSectionHeader(title: "частые вопросы")
                FAQRow(question: "Почему вердикт говорит «непонятно»?",
                       answer: "Ему нужно 3–4 дня записей, чтобы выучить интервалы. До этого он честно признаётся, что не знает, и не выдумывает.")
                TGDivider()
                FAQRow(question: "Куда делся счётчик лакомств?",
                       answer: "Убрали. Корм на занятия берётся из дневной порции, а не сверх неё, поэтому лимит не нужен — он мешал обучению.")
                TGDivider()
                FAQRow(question: "Где вкладка «Здоровье»?",
                       answer: "Она приходит с курсом лечения и уходит с ним: внизу «Здоровья» есть «Курс завершён». Записи остаются в истории и в отчёте врачу.")
                TGDivider()
                FAQRow(question: "Два человека отметили одно и то же",
                       answer: "Если два человека отметили одно и то же в пределах 20 минут, приложение покажет карточку слияния обоим. Чужое оно молча не перезаписывает.")
            }

            TGCard {
                TGSectionHeader(title: "что приложить к письму")
                Text(diagnostics).textStyle(AppFont.numeric(13, weight: .regular))
                TGExplainer(text: "Эти три строки помогают воспроизвести проблему. Никаких записей о собаке в них нет.")
            }
        }
        .navigationTitle("Поддержка")
        .navigationBarTitleDisplayMode(.large)
    }

    private func openMail() {
        let subject = "Togo \(settings.appVersion) — вопрос"
        let body = "\n\n---\n" + diagnostics
        var components = URLComponents(string: "mailto:\(Contacts.support)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components?.url else { return }
        // Обработчик обязателен: без него «не открылось» неотличимо
        // от «открылось», и единственным ответом человеку остаётся
        // системный алерт, за которым ничего нет.
        openURL(url) { открылось in
            guard !открылось else {
                UsageLog.note(.open, "support-mail", on: .dataPrivacy)
                return
            }
            UIPasteboard.general.string = "\(Contacts.support)\n\n\(diagnostics)"
            копияАдреса = Contacts.support
            Haptics.warning()
            UsageLog.note(.open, "support-mail", on: .dataPrivacy, outcome: .failed)
        }
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String

    var body: some View {
        DisclosureGroup {
            Text(answer)
                .textStyle(AppFont.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Token.Space.s4)
        } label: {
            Text(question).textStyle(AppFont.bodyEmphasis)
        }
        .tint(Token.Ink.secondary)
    }
}

struct AboutScreen: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        TGScreen {
            VStack(spacing: Token.Space.s8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Token.Status.doneText)
                Text("Togo").textStyle(AppFont.screenTitle)
                Text("версия \(settings.appVersion) (\(settings.buildNumber))").textStyle(AppFont.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Token.Space.s24)

            TGCard {
                Text("Зачем это").textStyle(AppFont.cardTitle)
                Text("Это дневник собаки, а не медкарта. Медицина включается режимом и в большинстве экранов её просто нет.")
                    .textStyle(AppFont.caption)
                Text("Названо в честь Того — ездовой собаки, которая прошла самый длинный и самый опасный отрезок гонки за сывороткой в Ном, а славу получил другой пёс.")
                    .textStyle(AppFont.caption)
            }

            TGCard {
                TGSectionHeader(title: "правила, которые мы себе поставили")
                ForEach(principles, id: \.self) { line in
                    HStack(alignment: .top, spacing: Token.Space.s8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Token.Status.doneText)
                            .padding(.top, 7)
                        Text(line).textStyle(AppFont.caption)
                    }
                }
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.large)
    }

    private let principles = [
        "Прерывать человека имеют право только доза, окно натощак и эскалация.",
        "То, без чего приложение молча вредит собаке, не продаётся.",
        "Приложение не знает лучше человека и говорит об этом прямо.",
        "Оценка описывает условия, а не животное.",
        "Молчаливой перезаписи и тихого удаления нет нигде.",
    ]
}

/// «Что нового» показывается один раз после обновления и всегда доступно
/// в настройках — а не всплывает поверх работы.
struct WhatsNewScreen: View {
    struct Release: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let items: [(String, String, String)]
    }

    static let releases: [Release] = [
        Release(version: "1.0.0", date: "август 2026", items: [
            ("target", "Тренажёр точности маркера", "Приложение стало секундомером и зеркалом, а не счётчиком корма: важна задержка маркера, а не количество кусочков."),
            ("figure.walk.departure", "«Как попросил»", "Один тап после выхода, который показывает, если лай вытесняет спокойный сигнал."),
            ("car", "Режим путешествия", "Включается датой и гаснет сам. Сборы считаются из веса и порции."),
            ("person.2", "Роли и дежурство", "Наблюдатель читает всё и не пишет, помощник пишет бытовое и не видит медицинского."),
        ]),
    ]

    var body: some View {
        TGScreen {
            ForEach(Self.releases) { release in
                TGCard {
                    HStack {
                        Text(release.version).textStyle(AppFont.cardTitle)
                        Spacer()
                        Text(release.date).textStyle(AppFont.micro)
                    }
                    TGDivider()
                    ForEach(release.items, id: \.1) { symbol, title, detail in
                        TGIconRow(symbol: symbol, title: .готовая(title), detail: .готовая(detail))
                    }
                }
            }
        }
        .navigationTitle("Что нового")
        .navigationBarTitleDisplayMode(.large)
    }
}
