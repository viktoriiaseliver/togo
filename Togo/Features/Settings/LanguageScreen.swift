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
    /// **`en` в списке есть, хотя английского перевода нет, и это
    /// не забывчивость — замер 05.10.2026.** В бандле иногда оказывается
    /// `en.lproj`, и внутри ровно один файл: `nlu.appintents`, который
    /// Xcode порождает для английского сам.
    ///
    /// Четыре сборки одного дня, и `en.lproj` был **в одной**:
    ///
    /// ```
    /// build/DerivedData   12:31   fr ru uk
    /// build/dd            12:39   fr ru uk EN
    /// build/dd-verify     12:52   fr ru uk      (каталог стёрт перед сборкой)
    /// Togo.xcarchive      28.09   fr ru uk
    /// ```
    ///
    /// **Причина не установлена.** Первая догадка — «чистая против
    /// инкрементальной» — опровергнута третьей строкой: она чистая
    /// и `en` в ней нет. Значит `Bundle.main.localizations` отдаёт то
    /// `["fr","ru","uk"]`, то `["en","fr","ru","uk"]` при одном коде,
    /// и предсказать этого мы не умеем.
    ///
    /// Ряд «English» поэтому появляется и обязан быть подписан. Он
    /// неактивен и помечен «перевод готовится»: `isTranslated` щупает
    /// каталог и ничего там не находит. Это и есть честный ответ —
    /// язык в бандле есть, перевода нет.
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
