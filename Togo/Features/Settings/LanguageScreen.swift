import SwiftUI

/// Язык интерфейса.
///
/// Языки берутся из бандла: в списке не появится то, чего в приложении нет.
/// Непереведённые помечены прямо — обещать перевод, которого нет, нельзя.
struct LanguageScreen: View {
    @Environment(Settings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var needsRestart = false

    private let names: [String: String] = [
        "ru": "Русский",
        "en": "English",
        "fr": "Français",
    ]

    var body: some View {
        List {
            Section {
                row(code: "", title: "Как в системе",
                    detail: systemLanguageName, isTranslated: true)
                ForEach(settings.availableLanguages, id: \.self) { code in
                    row(code: code,
                        title: names[code] ?? code.uppercased(),
                        detail: settings.isTranslated(code) ? nil : "перевод готовится",
                        isTranslated: settings.isTranslated(code))
                }
            } header: {
                Text("язык интерфейса")
            } footer: {
                Text("Язык применится при следующем запуске: перерисовать всё приложение на лету iOS не умеет, и притворяться, что умеет, мы не будем.")
            }

            if needsRestart {
                Section {
                    Label("Закройте и откройте приложение", systemImage: "arrow.clockwise")
                        .foregroundStyle(Token.Status.waitingText)
                }
            }

            Section {
                Button("Открыть языки в настройках iOS") { openSystemSettings() }
            } footer: {
                Text("То же самое можно выбрать в системных настройках — там же, где язык выбирается для любого приложения.")
            }

            Section {
                Text("Тексты приложения собраны в один документ для переводчика: `docs/TEXTS.md` в репозитории. Пока честно переведён только русский — машинный перевод для приложения про здоровье собаки хуже, чем одна аккуратная локаль.")
                    .textStyle(AppFont.caption)
            } header: {
                Text("как устроен перевод")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Token.Surface.screen)
        .navigationTitle("Язык")
        .navigationBarTitleDisplayMode(.large)
    }

    private var systemLanguageName: String? {
        guard let code = Locale.preferredLanguages.first?.prefix(2) else { return nil }
        return names[String(code)]
    }

    @ViewBuilder
    private func row(code: String, title: String, detail: String?, isTranslated: Bool) -> some View {
        Button {
            settings.preferredLanguage = code
            needsRestart = true
            Haptics.tap()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Token.Space.s2) {
                    Text(title)
                        .textStyle(AppFont.body.color(isTranslated ? Token.Ink.primary : Token.Ink.faint))
                    if let detail {
                        Text(detail).textStyle(AppFont.caption)
                    }
                }
                Spacer(minLength: Token.Space.s8)
                if settings.preferredLanguage == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Token.Action.primary)
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
