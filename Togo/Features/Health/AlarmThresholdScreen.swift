import SwiftUI
import SwiftData

/// Похоже, пора звонить.
///
/// Появляется, когда счёт сам дошёл до порога: три одинаковых инцидента
/// за шесть часов. Приложение не ставит диагноз и не решает за человека —
/// оно снимает две вещи, которые в три часа ночи мешают больше всего:
/// «уже пора или ещё нет» и «что говорить».
///
/// Отказ от звонка — не тупик: наблюдаем дальше с напоминанием через час.
struct AlarmThresholdScreen: View {
    let threshold: AlarmThreshold
    let dog: Dog
    let medications: [Medication]
    let events: [LogEvent]
    /// Отложить: наблюдаем и вернёмся через час.
    var onWatch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Открыт ли редактор телефонов поверх тревоги.
    @State private var вписываемТелефон = false

    private var vetText: String {
        AlarmThresholdAnalyzer.vetText(threshold, dog: dog,
                                       medications: medications, events: events)
    }

    var body: some View {
        TGSheet(title: "Похоже, пора звонить",
                subtitle: "записала, но одной записи мало") {
            episodesCard
            vetTextCard
            TGExplainer(text: "Порог задаёт счёт, а не догадка: \(AlarmThresholdAnalyzer.minimumEpisodes) эпизода за \(Int(threshold.window / 3600)) часов. Приложение не ставит диагнозов — решение всегда за врачом.")
        } footer: {
            if let phone = dog.clinicPhone ?? dog.vetPhone, !phone.isEmpty {
                TGButton(title: .готовая(String(localized: "Позвонить") + (dog.clinicName.map { " в \($0)" } ?? "")),
                         systemImage: "phone.fill") {
                    call(phone)
                }
            } else {
                // Кнопка обещает «вписать телефон» — и до 29.10.2026
                // только закрывала шторку. Человек в тревоге оставался
                // на «Сегодня» без номера и без подсказки, где его
                // вписать: экран «Документы» лежит на вкладке собаки
                // третьим уровнем. Теперь открывается ровно он, поверх
                // тревоги, и после «Готово» кнопка выше уже звонит —
                // `dog` тот же объект, и номер виден сразу.
                TGButton(title: "Некуда звонить · вписать телефон",
                         systemImage: "phone.badge.plus") { вписываемТелефон = true }
            }
            TGButton(title: "Наблюдать дальше · напомнить через час",
                     variant: .secondary, size: .medium) {
                onWatch()
                dismiss()
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $вписываемТелефон) {
            NavigationStack {
                DocumentsScreen(dog: dog)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { вписываемТелефон = false }
                        }
                    }
            }
        }
    }

    private var episodesCard: some View {
        TGCard(spacing: 0) {
            TGSectionHeader(title: .готовая(threshold.headline))
            ForEach(threshold.episodes) { episode in
                HStack(alignment: .top, spacing: Token.Space.s12) {
                    Text(Fmt.clock(episode.date))
                        .textStyle(AppFont.numeric(15))
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.vomitDetail?.title ?? "без подробностей")
                            .textStyle(AppFont.body)
                        Text(Fmt.gap(Date().timeIntervalSince(episode.date)) + " назад")
                            .textStyle(AppFont.caption)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Token.Size.tapTarget)
                if episode.id != threshold.episodes.last?.id { TGDivider() }
            }
        }
    }

    /// Готовый текст: его читают вслух, поэтому он лежит целиком
    /// и копируется одной кнопкой.
    private var vetTextCard: some View {
        TGCard {
            TGSectionHeader(title: "что сказать врачу",
                            subtitle: "собрано из того, что уже записано")
            Text(vetText).textStyle(AppFont.body).wraps()
            TGDivider()
            HStack(spacing: Token.Space.s16) {
                Button("Скопировать") { UIPasteboard.general.string = vetText }
                ShareLink(item: vetText) { Text("Отправить") }
            }
            .textStyle(AppFont.captionEmphasis.color(Token.Action.primary))
            .buttonStyle(.plain)
            .frame(minHeight: Token.Size.tapTarget)
        }
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { openURL(url) }
    }
}
