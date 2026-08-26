import SwiftUI
import SwiftData

/// Данные и приватность. Выгрузить всё и удалить всё — два действия,
/// оба без писем и ожидания.
struct DataPrivacyScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var dogs: [Dog]
    @Query private var events: [LogEvent]

    @State private var isConfirmingDelete = false
    @State private var deleted = false

    private var activeEvents: [LogEvent] { Diary.active(events) }

    var body: some View {
        TGScreen {
            TGCard {
                Text("Всё лежит на телефоне").textStyle(AppFont.cardTitle)
                Text("Аккаунта нет, серверов у нас нет. Записи хранятся в базе приложения и в общем хранилище с виджетами.")
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
                    preview: SharePreview("Дневник Того · CSV")
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
                TGExplainer(text: "Стирает записи, собак, схемы лечения и семью на этом устройстве. Отменить это будет нельзя — сначала выгрузи CSV, если он может пригодиться.")
            }

            if deleted {
                TGBanner(tone: .done, title: "Всё удалено",
                         subtitle: "На устройстве не осталось ни одной записи.",
                         systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("Данные")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Удалить все данные?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { deleteEverything() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи, собаки, схемы лечения и семья будут стёрты с этого устройства.")
        }
    }

    private func deleteEverything() {
        // Список полный намеренно: полагаться на каскад от собаки здесь
        // нельзя. Запас корма, течки и снимки документов в нём не значились
        // вовсе — то есть после «удалить все данные» фотография паспорта
        // оставалась лежать на телефоне.
        for model in [LogEvent.self, WeightEntry.self, DoseRecord.self, Medication.self,
                      CareTask.self, TrainingSession.self, TrainingStep.self, ProcedureSkill.self,
                      Trip.self, Episode.self, FamilyMember.self,
                      FoodStock.self, HeatRecord.self, DogDocument.self,
                      Dog.self] as [any PersistentModel.Type] {
            try? context.delete(model: model)
        }
        NotificationCenterService.cancelAll()
        deleted = true
        Haptics.warning()
    }
}

struct SupportScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(\.openURL) private var openURL

    private var diagnostics: String {
        """
        Того \(settings.appVersion) (\(settings.buildNumber))
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
                       answer: "Она появляется, когда в профиле включено лечение. У здоровой собаки медицины на главном нет вовсе.")
                TGDivider()
                FAQRow(question: "Две записи об одном событии",
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
        let subject = "Того \(settings.appVersion) — вопрос"
        let body = "\n\n---\n" + diagnostics
        var components = URLComponents(string: "mailto:support@togo.app")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components?.url { openURL(url) }
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
                    .foregroundStyle(Token.Action.primary)
                Text("Того").textStyle(AppFont.screenTitle)
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
                            .foregroundStyle(Token.Action.primary)
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
                        TGIconRow(symbol: symbol, title: title, detail: detail)
                    }
                }
            }
        }
        .navigationTitle("Что нового")
        .navigationBarTitleDisplayMode(.large)
    }
}
