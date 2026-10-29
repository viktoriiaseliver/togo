import SwiftUI
import SwiftData

/// «Готово: ты в дневнике у Виктории» — экран, а не тост.
///
/// **До 29.10.2026 успех приёма жил пять секунд** (`showUndo` в
/// `TogoApp`), а на свежем телефоне под ним стоял онбординг: человек
/// видел «Привет, давай заведём собаку», заводил свою — и оказывался
/// в собственном пустом дневнике. У мамы Виктории так и вышло: «она
/// получает уведомление, что в моём дневнике, но у неё ничего
/// не работает».
///
/// Экран говорит три вещи и ничего не просит заполнять: чей дневник,
/// что сейчас едет, что делать дальше. Пока собака из дневника
/// не приехала, он честно говорит «едет» и даёт «Забрать сейчас».
struct ВходВДневник: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.familySync) private var sync
    @Query private var dogs: [Dog]
    @State private var забираю = false

    /// Собака с записями — признак, что дневник приехал.
    private var приехала: Dog? {
        dogs.filter { !Diary.active($0.events).isEmpty }
            .max { $0.events.count < $1.events.count }
    }

    var body: some View {
        TGSheet(title: .готовая(ЧейДневник.имя.map { String(localized: "Ты в дневнике · \($0)") }
                                ?? String(localized: "Ты в общем дневнике")),
                subtitle: "приглашение принято") {
            TGCard {
                if let собака = приехала {
                    TGIconRow(symbol: "checkmark.circle",
                              title: .готовая(String(localized: "Дневник приехал · \(собака.displayName)")),
                              detail: "Лента, дозы и уход — общие. Твои отметки уходят в этот же дневник.")
                } else {
                    TGIconRow(symbol: "icloud.and.arrow.down",
                              title: "Дневник едет на этот телефон",
                              detail: "Обычно это минута. Свою собаку заводить не нужно — она приедет вместе с записями.",
                              tint: Token.Status.waitingText)
                    TGButton(title: забираю ? "Забираю…" : "Забрать сейчас", variant: .secondary,
                             size: .medium, systemImage: "arrow.clockwise", isEnabled: !забираю) {
                        Task {
                            забираю = true
                            await sync?.fetchNow()
                            забираю = false
                        }
                    }
                }
            }
            TGExplainer(text: "Проверить потом можно на экране «Семья»: там сверху написано, в чьём ты дневнике.")
        } footer: {
            TGButton(title: "Начать") { dismiss() }
        }
        .presentationDetents([.large])
    }
}
