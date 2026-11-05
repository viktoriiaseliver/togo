import SwiftUI
import UIKit
import SwiftData
import PhotosUI

/// Стул — самая частая запись. Один тап в норме, два — когда что-то не так.
/// Формы записываются сразу, без «Сохранить»; кнопка подтверждения появляется
/// только когда отмечены особенности: такая запись уходит в медицинскую часть.
struct StoolSheet: View {
    let dog: Dog?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var form: StoolForm?
    @State private var flags: Set<StoolFlag> = []
    @State private var created: LogEvent?
    @State private var фото: Data?

    private var usual: StoolForm? { Diary.usualStool(dog?.events ?? []) }

    var body: some View {
        TGSheet(title: "Стул", subtitle: .готовая(Fmt.clock(Date()))) {
            if let usual {
                Button { pick(usual) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: usual.symbol).foregroundStyle(Token.Ink.silhouette)
                        Text("Как всегда · \(usual.title.lowercased())").textStyle(AppFont.cardTitle)
                        Spacer()
                        Image(systemName: "checkmark.circle").foregroundStyle(Token.Action.doneText)
                    }
                    .foregroundStyle(Token.Ink.primary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Token.Action.doneQuiet, in: RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            TGSectionHeader(title: "форма")
            // Пять колонок — пока подписи в них помещаются. Ширина
            // колонки растёт вместе с кеглем, и на доступных размерах
            // сетка сама сходится к двум-трём: кадр 28.09 показал, что
            // при пяти жёстких «Колбаска» и «Кашица» остаются мелкими,
            // пока весь лист вырос.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: UIFontMetrics(forTextStyle: .body)
                                                       .scaledValue(for: 68)), spacing: 8)], spacing: 8) {
                ForEach(StoolForm.allCases, id: \.self) { candidate in
                    Button { pick(candidate) } label: {
                        VStack(spacing: 6) {
                            // Силуэты одним тёплым серо-коричневым: человек видит форму,
                            // а не цвет содержимого.
                            Image(systemName: candidate.symbol)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Token.Ink.silhouette)
                            // По токену, а не голым `Font.system(size:)`:
                            // голый размер настройку iOS не спрашивает.
                            Text(candidate.title)
                                .textStyle(AppFont.micro, color: Token.Ink.primary)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous)
                                .fill(form == candidate ? Token.Action.doneQuiet : Token.Surface.card)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            TGSectionHeader(title: "особенности", subtitle: "если ничего не отмечено — запись уже сохранена")
            TGChipGroup(
                items: StoolFlag.allCases,
                title: \.title,
                isSelected: { flags.contains($0) },
                tone: { $0.raisesAlarm ? .alarm : .neutral }
            ) { flag in
                toggle(flag)
            }

            if flags.contains(.blood) {
                TGBanner(
                    tone: .alarm,
                    title: "Кровь — это к врачу",
                    subtitle: Diary.suggestsVetReport(dog?.events ?? [])
                        ? "Второй жидкий с кровью подряд. Приложение может собрать выписку за эти дни."
                        : "Запись поднимется в истории и попадёт в отчёт врачу.",
                    systemImage: "cross.case"
                )
            }

            // **Фото ПОСЛЕ формы, и это не раскладка, а порядок
            // действий.** Выбор формы без особенностей записывает стул
            // и закрывает шторку (`pick`) — предложи снимок раньше,
            // и человек, который просто отметил «как всегда», получил
            // бы лишний шаг на самой частой записи дня.
            //
            // Кто снимает, тот уже выбрал форму и остался: у него либо
            // особенность, либо он сам открыл камеру.
            if form != nil {
                ФотоМомента(data: $фото)
            }

            TGExplainer(text: flags.isEmpty
                ? "Бристольская шкала 1–7 существует, но только в базе и в отчёте врачу — выбирать её руками не нужно."
                : "Подтверждение нужно потому, что запись с особенностью уходит в медицинскую часть и попадает в отчёт врачу.")
        } footer: {
            // Кнопка появляется, только когда отмечены особенности: без них
            // форма уже записана, и подтверждать нечего.
            if !flags.isEmpty {
                TGButton(title: "Подтвердить запись") { confirm() }
            }
        }
        .presentationDetents([.large])
        // **Снимок кладётся В ЗАПИСЬ СРАЗУ, а не при подтверждении.**
        // Без особенностей `confirm()` не зовётся вовсе: `pick`
        // записывает форму и закрывает шторку. Положи фото только
        // в `confirm` — и у человека, снявшего стул «как всегда»,
        // оно бы молча исчезло.
        //
        // Запись к этому моменту уже есть (её завёл `pick`), поэтому
        // `ensureEvent` здесь не заводит вторую.
        .onChange(of: фото) { _, новое in
            guard новое != nil, let event = created else { return }
            event.photo = новое
        }
    }

    private func toggle(_ flag: StoolFlag) {
        if flags.contains(flag) { flags.remove(flag) } else { flags.insert(flag) }
        Haptics.tap()
    }

    private func pick(_ candidate: StoolForm) {
        form = candidate
        Haptics.tap()
        // Форма пишется сразу: отменить можно тостом, «Сохранить» здесь лишний шаг.
        guard let event = ensureEvent() else { return }
        let былаФорма = event.stoolForm
        event.stoolForm = candidate
        // `record` выше сохранил само событие, а форма — правка ПОСЛЕ него.
        // До 04.11.2026 она жила в памяти до автосохранения, а тост
        // «Записано · Стул · …» звучал сразу. Выгрузи приложение — запись
        // осталась бы без формы, то есть без того, ради чего её делали.
        guard context.persist(otherwise: { event.stoolForm = былаФорма }) else {
            return неСохранилось()
        }
        if flags.isEmpty {
            appState.showUndo("Записано · Стул · \(candidate.title.lowercased())", eventID: event.id)
            dismiss()
        }
    }

    private func confirm() {
        guard let event = ensureEvent() else { return }
        let было = (форма: event.stoolForm, признаки: event.stoolFlags, снимок: event.photo)
        event.stoolForm = form
        event.stoolFlags = flags
        event.photo = фото
        // Признак крови решает `raisesAlarm`, то есть тревогу. Его нельзя
        // оставлять в памяти под тостом «Записано» — см. `pick`.
        guard context.persist(otherwise: {
            event.stoolForm = было.форма
            event.stoolFlags = было.признаки
            event.photo = было.снимок
        }) else { return неСохранилось() }
        Haptics.success()
        appState.showUndo("Записано · Стул", eventID: event.id)
        dismiss()
    }

    /// Запись заводится один раз и потом дополняется: форма выбирается
    /// первой, особенности — после.
    ///
    /// **Через `EventLog`, и возвращает `nil`, когда записывать нельзя.**
    /// Прежде здесь стоял `context.insert` напрямую, то есть мимо
    /// проверки права: гость-наблюдатель получал отказ на главном экране
    /// и записывал стул отсюда. Тост и отклик даёт вызывающий — он знает,
    /// дополнили запись или только начали.
    /// Отказ хранилища виден человеку — тот же текст, что у ухода
    /// (`CareScreen.неСохранилось`). Шторка остаётся открытой: выбор
    /// на экране, и нажать ещё раз можно, не вспоминая его.
    private func неСохранилось() {
        Haptics.warning()
        appState.showFailure("Не сохранилось · попробуй ещё раз")
    }

    private func ensureEvent() -> LogEvent? {
        if let created { return created }
        created = EventLog(context: context, appState: appState)
            .record(.stool, dog: dog, confirmation: nil, haptic: .none)
        return created
    }
}
