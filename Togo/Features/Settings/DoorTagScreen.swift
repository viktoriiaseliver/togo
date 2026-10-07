import SwiftUI

/// Метка у двери.
///
/// Момент выхода — единственный, в который приложение точно не откроют:
/// поводок в одной руке, собака тянет, телефон в кармане. Наклейка
/// на косяке решает это одним касанием: приложил телефон — прогулка
/// пошла, вернулся, приложил ещё раз — записалась.
///
/// Метка ничего не знает о человеке и не просит ни одного разрешения.
/// Геозона умеет то же самое, но требует доступ к геопозиции «всегда»
/// и меняет то, что приложение о себе заявляет: сейчас там честно
/// написано «сбор данных не ведётся». Пластиковый кружок за полсотни
/// рублей — честнее.
struct DoorTagScreen: View {
    private let steps: [(String, String)] = [
        ("Наклей метку у двери",
         "Подойдёт любая NFC-наклейка (NTAG213 и новее). Приклей на косяк или на крючок с поводком — туда, где рука и так проходит."),
        ("Открой «Команды» → «Автоматизация»",
         "Приложение «Команды» стоит на телефоне с завода. Внизу — вкладка «Автоматизация», кнопка «+»."),
        ("Выбери NFC и отсканируй метку",
         "Телефон предложит поднести метку и попросит её назвать — например «дверь»."),
        ("Добавь действие «Прогулка по метке»",
         "Найди в списке Togo. Выключи «Спрашивать до запуска» — иначе смысл теряется: придётся подтверждать."),
    ]

    var body: some View {
        TGScreen {
            TGCard {
                Text("Приложил — пошли").textStyle(AppFont.cardTitle)
                Text("Одно касание работает в обе стороны: прогулка не идёт — начнётся, идёт — закончится и запишется. У двери не надо вспоминать, что сейчас нажать.")
                    .textStyle(AppFont.caption)
            }

            TGCard(spacing: 0) {
                TGSectionHeader(title: "настроить один раз")
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { TGDivider() }
                    HStack(alignment: .top, spacing: Token.Space.s12) {
                        Text("\(index + 1)")
                            .textStyle(AppFont.numeric(15))
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: Token.Space.s2) {
                            Text(step.0).textStyle(AppFont.bodyEmphasis)
                            Text(step.1).textStyle(AppFont.caption).wraps()
                        }
                    }
                    .padding(.vertical, Token.Space.s10)
                }
            }

            TGCard {
                TGSectionHeader(title: "без метки — то же самое")
                TGIconRow(symbol: "mic",
                          title: "Голосом",
                          detail: "«Togo: прогулка» — Siri поймёт и на часах.")
                TGIconRow(symbol: "button.horizontal.top.press",
                          title: "Кнопка «Действие»",
                          detail: "На iPhone 15 Pro и новее — нажатие сбоку, не доставая телефон из кармана.")
                TGIconRow(symbol: "lock.iphone",
                          title: "Пункт управления",
                          detail: "Свайп и тап с заблокированного экрана.")
            }

            TGExplainer(text: "Метка не знает о тебе ничего: в ней записан только номер, по которому «Команды» узнают наклейку. Геопозицию Togo не спрашивает вовсе.")
        }
        .navigationTitle("Метка у двери")
        .posterHeader("Метка у двери")
        .navigationBarTitleDisplayMode(.large)
    }
}
