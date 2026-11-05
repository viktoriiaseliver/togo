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
            CinemaHeader("Данные", надпись: "где и кто видит", отступы: false)
            TGCard {
                Text("Всё лежит на телефоне").textStyle(AppFont.cardTitle)
                Text("Аккаунта нет, серверов у нас нет. Записи хранятся в базе приложения и в общем хранилище с виджетами.")
                    .textStyle(AppFont.caption)
                TGDivider()
                РядЧисел {
                    TGStat(count: activeEvents.count,
                           сЧислом: String(localized: "\(activeEvents.count) записей"))
                    // **Показываемые, а не все** (замер 26.10.2026).
                    //
                    // Стояло `dogs.count`, и человек с одной собакой
                    // читал «9 собак»: восемь пустых записей считались
                    // наравне с живой. Кадр —
                    // `Дизайн/кадры-приёмки/онбординг-26.10/контроль-данные-тот-же-пузырь-без-отмены.png`.
                    //
                    // Различитель, по которому это дефект, а не
                    // решение: **сосед по ТОЙ ЖЕ строке уже фильтрует** —
                    // рядом стоит `activeEvents`, а не все события.
                    // У решения «показываем всё, что в базе» был бы
                    // хозяин и довод, а здесь два счётчика одной
                    // карточки отвечают на разные вопросы.
                    //
                    // Тот же класс чинили в `SettingsScreen.swift:336-341`
                    // («ворота Pro считали безымянные наравне с собаками,
                    // счётчик в заголовке врал по той же причине») —
                    // **починили в одном месте и не перенесли
                    // в соседнее.**
                    TGStat(count: dogs.shownToPerson.count,
                           сЧислом: String(localized: "\(dogs.shownToPerson.count) собак"))
                    TGStat(count: Diary.daysOfData(activeEvents),
                           сЧислом: String(localized: "\(Diary.daysOfData(activeEvents)) дней"))
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
                    // Собирается в момент отправки, а не в `body`:
                    // разбор у `ВыгрузкаДневника`.
                    item: CSVFile(name: "togo-dnevnik.csv",
                                  выгрузка: ВыгрузкаДневника(container: context.container, вид: .весьДневник)),
                    preview: SharePreview("Дневник Togo · CSV")
                ) {
                    TGListRow(title: "Весь дневник · CSV", systemImage: "square.and.arrow.up")
                }
                TGDivider()
                ShareLink(
                    item: CSVFile(name: "togo-stul-vrachu.csv",
                                  выгрузка: ВыгрузкаДневника(container: context.container, вид: .стулВрачу)),
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
                TGExplainer(text: "Стирает записи, собак, схемы лечения и семью на этом устройстве. Отменить будет нельзя — сначала выгрузи CSV, если может пригодиться.")
            }

            if deleted {
                TGBanner(tone: .done, title: "Всё удалено",
                         subtitle: "На устройстве не осталось ни одной записи.",
                         systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("Данные")
        .cinemaScreen(экран: .sub("privacy"))
        .usageScreen(.dataPrivacy)
        .confirmationDialog("Удалить все данные?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { deleteEverything() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записи, собаки, схемы лечения и семья будут стёрты с этого устройства.")
        }
    }

    private func deleteEverything() {
        var неУдалось = 0
        // Список полный намеренно: полагаться на каскад от собаки здесь
        // нельзя. Запас корма, течки и снимки документов в нём не значились
        // вовсе — то есть после «удалить все данные» фотография паспорта
        // оставалась лежать на телефоне.
        for model in [LogEvent.self, WeightEntry.self, DoseRecord.self, Medication.self,
                      CareTask.self, TrainingSession.self, TrainingStep.self, ProcedureSkill.self,
                      Trip.self, Episode.self, FamilyMember.self,
                      FoodStock.self, HeatRecord.self, DogDocument.self, DayOut.self,
                      // Медслой и справочник клиник — пять моделей, которых
                      // в списке не было (аудит 28.10.2026): после «удалить
                      // все данные» на телефоне оставались анализы, визиты,
                      // диагнозы, назначения и клиники.
                      LabResult.self, VetVisit.self, Diagnosis.self, Prescription.self,
                      Clinic.self,
                      Dog.self] as [any PersistentModel.Type] {
            do {
                try context.delete(model: model)
            } catch {
                неУдалось += 1
            }
        }
        // `try?` выбрасывал отказ, и экран говорил «Всё удалено» при любом
        // исходе. Не удалилась хоть одна модель — говорим правду и не
        // трогаем ни отметки, ни напоминания: человек нажмёт ещё раз.
        guard неУдалось == 0 else {
            Haptics.warning()
            appState.showFailure(String(localized: "Удалилось не всё · нажми ещё раз"))
            return
        }

        // Отметки в UserDefaults стираются ТОЖЕ, и это решение Виктории
        // 24.10.2026: «как при первой установке».
        //
        // Без этого «удалить все данные» стирало шестнадцать моделей
        // и не трогало в UserDefaults ничего. Заготовки навыков уезжали
        // вместе с `ProcedureSkill`, а галочка «заготовки уже созданы»
        // оставалась `true` — и человек после полного удаления оставался
        // **без навыков и без того, что их когда-то заводили**.
        //
        // > **Данные и отметка о данных жили в разных хранилищах,
        // > и стирало их разное.** Флаг переживал удаление по устройству,
        // > а не по решению: `@AppStorage` просто не входит в `context`.
        //
        // Список поимённый, а не `removePersistentDomain`: тот снёс бы
        // и выбранный язык, и согласия, и настройки уведомлений — всё,
        // что человек про удаление данных не просил.
        for ключ in ["procedureSkills.seeded"] {
            UserDefaults.standard.removeObject(forKey: ключ)
        }

        NotificationCenterService.cancelAll()
        deleted = true
        Haptics.warning()
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
            CinemaHeader("Поддержка", отступы: false)
            TGCard {
                Text("Отвечает человек").textStyle(AppFont.cardTitle)
                Text("Обычно в течение двух рабочих дней. Если что-то в приложении мешает ухаживать за собакой — пиши сразу, это важнее фич.")
                    .textStyle(AppFont.caption)
                TGButton(title: "Написать в поддержку", size: .medium, systemImage: "envelope") {
                    openMail()
                }
                if let копияАдреса {
                    TGBanner(tone: .alarm, title: "Почта на телефоне не настроена",
                             // Второй случай того же класса, найден обходом
                             // по `.готовая(` с кириллическим литералом,
                             // а не сторожем: сторож назвал один файл,
                             // а форма оказалась общая на два экрана.
                             subtitle: .готовая(String(localized: "Адрес скопирован: \(копияАдреса). Напиши с любого другого устройства — и приложи три строки ниже.")),
                             systemImage: "envelope.badge.shield.half.filled")
                }
            }

            TGCard {
                TGSectionHeader(title: "частые вопросы")
                FAQRow(question: "Почему вердикт говорит «непонятно»?",
                       answer: "Ему нужно 3–4 дня записей, чтобы выучить интервалы. До этого он честно признаётся, что не знает, и не выдумывает.")
                TGDivider()
                // Ответ переписан 03.11.2026: он объяснял пропажу
                // счётчика через занятия, которых в приложении нет
                // с 28.10 (`82ba1e46`). Сам вопрос остаётся живым —
                // лакомства никуда не делись (`TreatSheet`, флаг
                // `trainingFoodFromPortion`, `ProfileScreen.marker`).
                FAQRow(question: "Куда делся счётчик лакомств?",
                       answer: "Убрали. Лакомства можно брать из дневной порции, а не сверх неё, — тогда лимит не нужен.")
                TGDivider()
                FAQRow(question: "Где вкладка «Здоровье»?",
                       answer: "Она у того, кому разрешено видеть медицинское. У помощника её нет. Курс можно завершить внизу «Здоровья» — записи остаются в истории и в отчёте врачу, а вкладка никуда не денется.")
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
        .cinemaScreen(экран: .sub("support"))
    }

    private func openMail() {
        // Тему человек видит в окне почты до отправки. Номер версии
        // внутри ключа нарочно: он нужен поддержке, и отделять его
        // в отдельную строку значило бы собирать тему из двух кусков
        // в каждом языке — а порядок слов везде свой.
        let subject = String(localized: "Togo \(settings.appVersion) — вопрос")
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

/// Вопрос и ответ — **ключи каталога, а не `String`**, и это замер
/// 03.11.2026, а не стиль.
///
/// Было `question: String` / `answer: String`, а читаются они
/// `Text(question)` и `Text(answer)`. У `Text` две перегрузки, и выбор
/// между ними делает ТИП аргумента: `LocalizedStringKey` спрашивает
/// каталог, `StringProtocol` рисует дословно. Литералы стояли
/// на месте вызова, но приходили сюда через параметр `String` —
/// к моменту `Text` это уже была переменная.
///
/// Все восемь строк (четыре вопроса и четыре ответа) **уже лежали
/// в каталоге переведёнными на en/fr/kk/uk** — замер по
/// `TogoShared/Resources/Localizable.xcstrings`, отрицательный
/// контроль на заведомо отсутствующем ключе. То есть переводы были
/// оплачены и не доезжали: экран «Данные и приватность» открывают
/// намеренно, и открывал его кто угодно на любом языке — а частые
/// вопросы отвечали по-русски.
///
/// Новых ключей правка не заводит, каталог не трогает.
///
/// Долг этого файла в `LocalizationDebtTests` (9) закрывается
/// не полностью: ниже остаётся `Release.date` («август 2026»,
/// `DataPrivacyScreen.swift:385`), тоже `String`. Потолок в храповике
/// **не понижен нарочно** — остаток я считал разбором, а не прогоном
/// сторожа, и понижать число по невымеренному остатку значит
/// заводить ложный красный следующему.
private struct FAQRow: View {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey

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
            CinemaHeader("О приложении", отступы: false)
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
        .cinemaScreen(экран: .sub("about"))
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
    /// # Подписи — `LocalizedStringKey`, а не `String` (замер 03.11.2026)
    ///
    /// Было `[(String, String, String)]`, и показ шёл через
    /// `TGIconRow(title: .готовая(title))`. `готовая` строит
    /// `LocalizedStringKey` из готовой строки **дословно** — то есть
    /// каталог не спрашивается вовсе, и экран «Что нового» рисовался
    /// по-русски на всех языках.
    ///
    /// **Все шесть ключей в каталоге при этом ЛЕЖАЛИ, на четырёх
    /// языках.** Перевод был куплен и не доезжал: дороги к нему
    /// не было. Тот же класс, что закрывали сегодня в тринадцати
    /// тостах — `showUndo(_ message: String)`.
    ///
    /// > **Тип `String` у подписи — это не «ещё не локализовано»,
    /// > а «локализовано не будет».** Компилятор молчит, ключ
    /// > в каталоге есть, грепом место выглядит здоровым. Лечится
    /// > не обёрткой на месте показа, а типом в объявлении: литерал
    /// > в `LocalizedStringKey` становится ключом сам.
    ///
    /// `symbol` остаётся `String` — это имя SF Symbol, не подпись.
    ///
    /// **Кортеж заменён типом, и это тоже замер, а не вкус.** Пока
    /// пункт был `(String, String, String)`, `ForEach` опирался
    /// на `id: \.1` — то есть на саму подпись. С переводом так нельзя:
    /// `LocalizedStringKey` **не `Hashable`**, и компилятор сказал это
    /// прямо, когда я сменил тип и оставил прежний `id`. Идентичность
    /// строки списка не должна жить в её тексте: сегодня это подпись,
    /// завтра перевод, а послезавтра две одинаковые.
    struct Release: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let items: [Пункт]

        struct Пункт: Identifiable {
            let id = UUID()
            let symbol: String
            let title: LocalizedStringKey
            let detail: LocalizedStringKey
        }
    }

    static let releases: [Release] = [
        // «Тренажёр точности маркера» снят 03.11.2026. `MARKETING_VERSION`
        // в `Configuration/Shared.xcconfig:15` по-прежнему 1.0.0, то есть
        // это не история прошлого выпуска, а список того, что человек
        // получит ПРИ УСТАНОВКЕ. Занятий в приложении нет с 28.10
        // (`82ba1e46`), и первой же строкой «Что нового» обещало их.
        Release(version: "1.0.0", date: "август 2026", items: [
            Release.Пункт(symbol: "figure.walk.departure", title: "«Как попросил»", detail: "Один тап после выхода, который показывает, если лай вытесняет спокойный сигнал."),
            Release.Пункт(symbol: "car", title: "Режим путешествия", detail: "Включается датой и гаснет сам. Сборы считаются из веса и порции."),
            Release.Пункт(symbol: "person.2", title: "Роли и дежурство", detail: "Наблюдатель читает всё и не пишет, помощник пишет бытовое и не видит медицинского."),
        ]),
    ]

    var body: some View {
        TGScreen {
            CinemaHeader("Что нового", отступы: false)
            ForEach(Self.releases) { release in
                TGCard {
                    HStack {
                        Text(release.version).textStyle(AppFont.cardTitle)
                        Spacer()
                        Text(release.date).textStyle(AppFont.micro)
                    }
                    TGDivider()
                    ForEach(release.items) { пункт in
                        TGIconRow(symbol: пункт.symbol, title: пункт.title, detail: пункт.detail)
                    }
                }
            }
        }
        .navigationTitle("Что нового")
        .cinemaScreen(экран: .sub("whatsnew"))
    }
}
