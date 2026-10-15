import SwiftUI

/// Язык интерфейса.
///
/// Языки берутся из бандла: в списке не появится то, чего в приложении нет.
/// Непереведённые помечены прямо — обещать перевод, которого нет, нельзя.
struct LanguageScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var needsRestart = false

    /// Имя языка — на самом языке, а не на русском.
    ///
    /// **Список обязан покрывать весь бандл.** Ряд без имени не падает
    /// и не пустует: он подписывается кодом в верхнем регистре. 05.10.2026
    /// украинский так и стоял — «UK» между «Русский» и «Français», —
    /// при 2044 переведённых строках. Отсутствие имени выглядит
    /// не дырой, а решением: будто язык служебный.
    ///
    /// Сторож — `LocalizationCoverageTests.уЯзыковБандлаЕстьИмена`.
    ///
    /// Словарь имён оставлен полным нарочно: он не решает, что
    /// предлагать, — решает `Settings.предлагаемыеЯзыки`.
    ///
    /// ## Три утверждения, стоявшие здесь, померены 15.10.2026 и сняты
    ///
    /// Прежняя редакция объясняла, почему в списке есть «English»,
    /// и объясняла тремя утверждениями. Все три оказались ложными,
    /// и по-разному:
    ///
    /// ```
    /// «en.lproj … внутри ровно один файл: nlu.appintents»
    ///     ЛОЖНО СЕГОДНЯ: 3 файла, Localizable.strings 287 786 Б,
    ///     2175 ключей. Было верно, когда писалось
    /// «Он неактивен»
    ///     ЛОЖНО С РОЖДЕНИЯ: `.disabled` в этом файле 0 вхождений
    ///     (контроль `buttonStyle` 1, контроль по SettingsScreen 1).
    ///     `isTranslated` красит текст, ряд не запирает никогда
    /// «помечен „перевод готовится"»
    ///     ЛОЖНО СЕГОДНЯ: щуп «Просится» даёт en 'Needs to go out?',
    ///     fr 'Envie de sortir ?', uk 'Проситься' — все три ≠ щупу,
    ///     значит `isTranslated` == true у ВСЕХ ТРЁХ, и пометки
    ///     не получал ни один язык
    /// ```
    ///
    /// > **Пометка исчезла сама, в момент успеха.** Завезли каталог —
    /// > щуп стал попадать, и приложение молча начало предлагать три
    /// > языка как готовые, при 313 ключах без перевода из 2522.
    ///
    /// Про «четыре сборки одного дня, и `en.lproj` был в одной» —
    /// причина установлена и лежит в `Tools/check_bundle_languages.sh`:
    /// это были не четыре сборки с разным составом, а одна фаза
    /// копирования ресурсов, остановленная в разных местах.
    ///
    /// ## Что здесь сейчас
    ///
    /// Предлагается **только русский** (решение Виктории 15.10.2026,
    /// довод и цена — у `Settings.предлагаемыеЯзыки`). Поэтому ветка
    /// «перевод готовится» ниже **сегодня недостижима**: до неё доходят
    /// только языки из списка предложения, а там один русский,
    /// и `isTranslated("ru")` возвращает `true` без всяких щупов.
    /// Ветка оставлена, а не удалена, чтобы возвращение языка стоило
    /// одного слова в `предлагаемыеЯзыки`, а не переписывания экрана.
    ///
    /// **Выход для того, кто уже выбрал французский и обновился:** ряд
    /// «Как в системе» на месте и возвращает язык системы. Отдельного
    /// ряда «ваш язык больше не предлагается» нет — названо открытым,
    /// а не забыто.
    static let names: [String: String] = [
        "ru": "Русский",
        "en": "English",
        "fr": "Français",
        "uk": "Українська",
    ]

    var body: some View {
        List {
            Section {
                // Подпись ряда и имя языка — разные вещи, и разделены
                // они здесь намеренно. «Как в системе» и «перевод
                // готовится» — ключи каталога, и приходить на экран
                // обязаны переведёнными; имя языка переводить нельзя
                // вовсе, «Українська» остаётся собой на любом экране.
                // `Text(строка)` со ЗНАЧЕНИЕМ типа `String` рисует
                // текст дословно, мимо каталога, — поэтому `Text`
                // строится здесь, а не внутри `row`, где тип подписи
                // стёр бы разницу. Французский и украинский этих двух
                // строк лежали в каталоге готовыми и до 05.10.2026
                // не доезжали до экрана ни разу.
                row(code: "", title: Text("Как в системе"),
                    detail: systemLanguageName.map { Text(verbatim: $0) },
                    isTranslated: true)
                ForEach(settings.availableLanguages, id: \.self) { code in
                    row(code: code,
                        title: Text(verbatim: Self.names[code] ?? code.uppercased()),
                        detail: settings.isTranslated(code) ? nil : Text("перевод готовится"),
                        isTranslated: settings.isTranslated(code))
                }
            } header: {
                Text("язык интерфейса")
            } footer: {
                Text("Язык применится при следующем запуске: перерисовать всё приложение на лету iOS не умеет, и притворяться, что умеет, мы не будем.")
            }

            if needsRestart {
                Section {
                    Label("Закрой и открой приложение", systemImage: "arrow.clockwise")
                        .foregroundStyle(Token.Status.waitingText)
                }
            }

            Section {
                Button("Открыть языки в настройках iOS") { openSystemSettings() }
            } footer: {
                Text("То же самое можно выбрать в системных настройках — там же, где язык выбирается для любого приложения.")
            }

            Section {
                // Считать языки в тексте нельзя: список меняется, а фраза
                // остаётся — и в день, когда добавится язык, приложение
                // начнёт говорить о себе неправду. Довод остаётся, счёт
                // уходит; сами языки человек видит списком выше.
                Text("Языков мало намеренно: машинный перевод в приложении про здоровье собаки хуже, чем язык, сделанный целиком.")
                    .textStyle(AppFont.caption)
            } header: {
                Text("как устроен перевод")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .navigationTitle("Язык")
        .posterHeader("Язык")
        .navigationBarTitleDisplayMode(.large)
    }

    private var systemLanguageName: String? {
        guard let code = Locale.preferredLanguages.first?.prefix(2) else { return nil }
        return Self.names[String(code)]
    }

    @ViewBuilder
    private func row(code: String, title: Text, detail: Text?, isTranslated: Bool) -> some View {
        Button {
            settings.preferredLanguage = code
            needsRestart = true
            Haptics.tap()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    title
                        .textStyle(AppFont.body.color(isTranslated ? Token.Ink.primary : Token.Ink.secondary))
                    if let detail {
                        detail.textStyle(AppFont.caption)
                    }
                }
                Spacer(minLength: Token.Space.s8)
                if settings.preferredLanguage == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Token.Status.doneText)
                        .accessibilityLabel("Выбрано")
                }
            }
            .frame(minHeight: Token.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
