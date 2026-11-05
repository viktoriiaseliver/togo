import SwiftUI
import UIKit
import SwiftData
import PhotosUI

/// Правка события. Удаление обратимо 5 секунд, и в истории остаётся след,
/// что запись была и кто её убрал.
struct EventEditSheet: View {
    let eventID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    /// Одна запись, отобранная БАЗОЙ по идентификатору.
    ///
    /// **Прежде здесь стоял `@Query` без отбора, а запись искалась
    /// перебором: `events.first { $0.id == eventID }`.** Замер
    /// 28.10.2026 по жалобе «виснет»: свойство `event` зовётся в теле
    /// этого листа **76 раз**, и каждое обращение проходило весь
    /// дневник. При 1400 записях это порядка ста тысяч сравнений
    /// идентификаторов на одно открытие листа — плюс сам `@Query`
    /// поднимал в память весь дневник, чтобы вернуть одну строку.
    ///
    /// > Отбор, сделанный в коде после запроса, выглядит так же,
    /// > как отбор, сделанный запросом, и стоит несравнимо дороже:
    /// > первый платит за все строки, второй — за одну.
    @Query private var events: [LogEvent]
    /// Отметки этой прогулки — тоже отбором, а не фильтром по всему.
    @Query private var отметкиПрогулки: [LogEvent]
    @Query private var careTasks: [CareTask]
    @Query private var medications: [Medication]
    @Query private var trainingSessions: [TrainingSession]
    @State private var asking = false
    /// Слепок записи на момент открытия — по нему видно, правили её или
    /// просто открыли посмотреть. В журнал действий уходит только факт
    /// правки; ни граммов, ни текста заметки в слепке нет.
    @State private var openedAs: String?

    init(eventID: UUID) {
        self.eventID = eventID
        // Предикаты строятся здесь, потому что `@Query` не видит
        // свойств типа в объявлении: отбор по `eventID` возможен
        // только через собственный инициализатор.
        _events = Query(filter: #Predicate<LogEvent> { $0.id == eventID })
        _отметкиПрогулки = Query(filter: #Predicate<LogEvent> {
            $0.walkEventID == eventID && $0.deletedAt == nil
        })
    }

    private var event: LogEvent? { events.first }

    /// Что в записи может измениться. Числа и текст не пишем — только то,
    /// заполнены они или нет, и на сколько.
    private func fingerprint(_ event: LogEvent) -> String {
        var parts: [String] = []
        parts.append(String(Int(event.date.timeIntervalSince1970)))
        parts.append(event.outcomeRaw ?? "-")
        parts.append(event.stoolFormRaw ?? "-")
        parts.append(event.stoolFlagsRaw.sorted().joined(separator: ","))
        parts.append(event.grams.map(String.init) ?? "-")
        parts.append(event.milliliters.map(String.init) ?? "-")
        parts.append(event.durationSeconds.map(String.init) ?? "-")
        parts.append(String(event.note?.count ?? 0))
        return parts.joined(separator: "|")
    }

    /// Свои записи ведут все, кому это разрешено; править и удалять
    /// уже записанное — отдельное право.
    private var canEdit: Bool { appState.can(.editRecords) }

    var body: some View {
        TGSheet(title: event.map { .готовая($0.kind.title) } ?? "Запись",
                      // «синхронизировано» отсюда убрано вместе с галочкой:
                      // обмена между устройствами пока нет, и говорить о нём
                      // нельзя.
                      subtitle: event.map { "Записала \($0.authorName) в \(Fmt.clock($0.date))" }) {
            // Плашка была и адрес называла верно («Семья»), а имя
            // права — нет. Из трёх таких плашек в дереве ни одна
            // не называла права по имени каталога, и все три написаны
            // своими словами — то есть разошлись бы молча ещё и между
            // собой.
            if !canEdit { ПлашкаПрава(право: .editRecords) }
            // Снимок целиком — здесь, а не в ленте: лента показывает
            // только значок «есть фото», и строка ведёт сюда.
            //
            // Править фото может лишь тот, кому разрешено править
            // записи: снимок — часть записи, и отдельного права у него
            // нет. Чужому показываем, но не даём трогать.
            if let event, event.photo != nil || canEdit {
                ФотоМомента(data: Binding(get: { event.photo },
                                          set: { новое in
                    guard canEdit else { return }
                    event.photo = новое
                }))
            }
            if let event {
                TGCard(padding: 4) {
                    VStack(spacing: 0) {
                        // Запись в будущем ломает всё, что считается
                        // от «последнего раза»: вердикт решит, что собака
                        // только что выходила. В живом дневнике такая
                        // запись уже появилась — время выставили вечером.
                        // День правится наравне с часом (28.09). Раньше
                        // стояло только `.hourAndMinute`, и запись,
                        // сделанную не в тот день, нельзя было перенести
                        // вовсе — её удаляли и заводили заново, теряя
                        // и автора, и след правки.
                        //
                        // Верхняя граница прежняя: запись в будущем ломает
                        // всё, что считается «от последнего раза», и такая
                        // запись в живом дневнике уже появлялась — время
                        // выставили вечером.
                        DatePicker(event.kind == .walk ? "Вышли" : "Время", selection: Binding(
                            get: { event.date },
                            set: { setStart(min($0, .now), on: event) }
                        ), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .textStyle(AppFont.body)
                        .frame(minHeight: Token.Size.tapTarget)

                        if event.kind == .walk {
                            // Спрашиваем то, что человек знает: во сколько
                            // ушли и во сколько вернулись. Длительность
                            // считается сама.
                            //
                            // Раньше рядом со временем начала стоял отдельный
                            // шаговик «сколько гуляли» — и, поправив начало,
                            // приходилось руками пересчитывать длительность,
                            // иначе прогулка молча уезжала концом вперёд.
                            TGDivider()
                            DatePicker("Вернулись", selection: Binding(
                                get: { walkEnd(of: event) },
                                set: { setWalkEnd($0, on: event) }
                            ), in: event.date...Date(), displayedComponents: .hourAndMinute)
                            .textStyle(AppFont.body)
                            .frame(minHeight: Token.Size.tapTarget)

                            TGDivider()
                            HStack {
                                Text("Гуляли").textStyle(AppFont.body)
                                Spacer()
                                Text(Fmt.duration(Double(event.durationSeconds ?? 0)))
                                    .textStyle(AppFont.numeric(15))
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                        }

                        if event.kind == .outing {
                            TGDivider()
                            Picker("Результат", selection: Binding(
                                get: { event.outcome ?? .none },
                                set: { event.outcome = $0 }
                            )) {
                                ForEach(OutingOutcome.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .textStyle(AppFont.body)
                            .frame(minHeight: Token.Size.tapTarget)
                        }

                        // Значение записи. Без него правка была
                        // декоративной: время и заметку поменять можно,
                        // а те самые граммы, ради которых запись и делали, —
                        // нет. В живом дневнике это видно дважды за день:
                        // человек записывал 65 г, хотел 75, не находил где
                        // поправить и удалял запись, чтобы записать заново.
                        value(of: event)

                        TGDivider()
                        HStack {
                            Text("Заметка").textStyle(AppFont.body)
                            Spacer()
                            TextField("добавить", text: Binding(
                                get: { event.note ?? "" },
                                set: { event.note = $0.isEmpty ? nil : $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .textStyle(AppFont.body)
                        }
                        .frame(minHeight: Token.Size.tapTarget)
                    }
                    .padding(.horizontal, 12)
                }
                .disabled(!canEdit)

                originCard
                askOwner(about: event)

                if canEdit {
                TGButton(title: .готовая(deleteTitle(for: event)), variant: .destructive,
                         size: .medium, systemImage: "trash") {
                    delete(event)
                }
                TGExplainer(text: .готовая(deleteExplainer(for: event)))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { openedAs = event.map(fingerprint) }
        .onDisappear {
            // Правка сохраняется прямо через привязки полей, отдельной
            // кнопки «Готово» нет. Поэтому факт правки виден только так:
            // сравнением того, с чем открыли, и того, с чем ушли.
            guard let event, let openedAs, fingerprint(event) != openedAs else { return }
            UsageLog.note(.edit, event.kind.rawValue)
        }
    }

    /// Спросить хозяйку прямо из записи.
    ///
    /// Ситтер не сочиняет сообщение — выбирает готовый вопрос, контекст
    /// едет вложением. Сочинять текст в чужом доме, когда собака не доела,
    /// человек стесняется и потому молчит; а молчание здесь дороже всего.
    @ViewBuilder
    private func askOwner(about event: LogEvent) -> some View {
        if !appState.can(.manageFamily) {
            Button { asking = true } label: {
                TGCard {
                    TGListRow(title: "Спросить хозяйку", systemImage: "bubble.left.and.text.bubble.right",
                              accessory: .none)
                    TGExplainer(text: "Запись прикрепится к вопросу сама.")
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $asking) {
                AskOwnerSheet(event: event, ownerName: ownerName)
            }
        }
    }

    /// Кому писать. Владелец в семье один, и искать его руками незачем.
    private var ownerName: String {
        (try? context.fetch(FetchDescriptor<FamilyMember>()))?
            .first { $0.role == .owner }?.name ?? String(localized: "хозяйку")
    }

    /// Что именно записали: граммы, миллилитры, форма стула, что случилось.
    ///
    /// У каждого вида записи своя главная величина, и править надо
    /// именно её — а не только час и подпись.
    @ViewBuilder
    private func value(of event: LogEvent) -> some View {
        switch event.kind {
        case .meal, .treat:
            TGDivider()
            HStack {
                Text(event.kind == .meal ? "Съел" : "Лакомство").textStyle(AppFont.body)
                Spacer()
                TGStepper(value: Binding(get: { event.grams ?? 0 },
                                         set: { event.grams = $0 }),
                          unit: "г",
                          step: event.kind == .meal ? 5 : 1,
                          range: 0...600,
                          compact: true)
            }
            .frame(minHeight: Token.Size.tapTarget)

        case .water:
            TGDivider()
            HStack {
                Text("Выпил").textStyle(AppFont.body)
                Spacer()
                TGStepper(value: Binding(get: { event.milliliters ?? 0 },
                                         set: { event.milliliters = $0 }),
                          unit: "мл", step: 50, range: 0...2000, compact: true)
            }
            .frame(minHeight: Token.Size.tapTarget)

        case .stool:
            TGDivider()
            Picker("Форма", selection: Binding(get: { event.stoolForm ?? .sausage },
                                               set: { event.stoolForm = $0 })) {
                ForEach(StoolForm.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .textStyle(AppFont.body)
            .frame(minHeight: Token.Size.tapTarget)

        case .incident:
            TGDivider()
            Picker("Что случилось", selection: Binding(get: { event.incidentKind ?? .other },
                                                      set: { event.incidentKind = $0 })) {
                ForEach(IncidentKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .textStyle(AppFont.body)
            .frame(minHeight: Token.Size.tapTarget)

        case .weight:
            EmptyView()

        default:
            EmptyView()
        }
    }

    /// Отметки, сделанные внутри этой прогулки.
    ///
    /// Отбор делает база (`отметкиПрогулки`), а не фильтр по всему
    /// дневнику. Проверка вида остаётся здесь: у записи, которая
    /// не прогулка, отметок не бывает по смыслу, и предикат про это
    /// не знает.
    private func marks(of event: LogEvent) -> [LogEvent] {
        guard event.kind == .walk else { return [] }
        return отметкиПрогулки
    }

    private func deleteTitle(for event: LogEvent) -> String {
        let count = marks(of: event).count
        return count == 0 ? String(localized: "Удалить запись") : String(localized: "Удалить прогулку и \(count) отметки")
    }

    private func deleteExplainer(for event: LogEvent) -> String {
        marks(of: event).isEmpty
            ? String(localized: "Удаление можно отменить 5 секунд — потом запись уйдёт из ленты совсем. Чтобы поправить, а не убрать, меняй значения выше: они сохраняются сразу.")
            : String(localized: "Прогулка удалится вместе с тем, что в ней отмечено: они записаны как одно целое. Отменить можно 5 секунд.")
    }

    /// Удаление прогулки забирает с собой её отметки.
    ///
    /// Раньше их приходилось искать и удалять по одной: в живом дневнике
    /// видно, как человек убирал одну прогулку тремя действиями подряд.
    private func delete(_ event: LogEvent) {
        let now = Date()
        let who = appState.currentUserName
        let removed = marks(of: event) + [event]
        for target in removed {
            target.deletedAt = now
            target.deletedBy = who
        }
        guard context.persist(otherwise: {
            for target in removed {
                target.deletedAt = nil
                target.deletedBy = nil
            }
        }) else {
            Haptics.warning()
            return appState.showFailure("Удаление не сохранилось · попробуй ещё раз")
        }
        Haptics.warning()
        UsageLog.note(.delete, event.kind.rawValue)
        appState.showUndoRestore("Удалено · \(event.kind.title)",
                                 eventIDs: removed.map(\.id))
        dismiss()
    }

    /// Когда вернулись с прогулки.
    private func walkEnd(of event: LogEvent) -> Date {
        event.date.addingTimeInterval(Double(event.durationSeconds ?? 0))
    }

    /// Поправили время возвращения — пересчитываем длительность.
    private func setWalkEnd(_ end: Date, on event: LogEvent) {
        event.durationSeconds = max(0, Int(end.timeIntervalSince(event.date)))
    }

    /// Поправили время выхода.
    ///
    /// У прогулки конец остаётся на месте: человек помнит, когда вернулся,
    /// и передвигать это за него нельзя. Меняется длительность.
    private func setStart(_ start: Date, on event: LogEvent) {
        guard event.kind == .walk, event.durationSeconds != nil else {
            event.date = start
            return
        }
        let end = walkEnd(of: event)
        event.date = start
        event.durationSeconds = max(0, Int(end.timeIntervalSince(start)))
    }

    /// Откуда взялась запись.
    ///
    /// Связи с задачей ухода, препаратом и занятием писались в модель
    /// и не читались никем: из ленты нельзя было понять, какое напоминание
    /// отметили и какое занятие оставило след. Особенно это било по дозам:
    /// препарат могли переименовать, а в записи оставалось старое имя.
    @ViewBuilder
    private var originCard: some View {
        if let origin {
            TGCard(spacing: 0) {
                TGSectionHeader(title: "откуда эта запись")
                TGListRow(title: .готовая(origin.title), value: origin.detail.map { .готовая($0) },
                          systemImage: origin.symbol, accessory: .none)
                TGExplainer(text: .готовая(origin.explainer))
            }
        }
    }

    private struct Origin {
        var title: String
        var detail: String?
        var symbol: String
        var explainer: String
    }

    private var origin: Origin? {
        guard let event else { return nil }

        if let id = event.careTaskID, let task = careTasks.first(where: { $0.id == id }) {
            return Origin(title: task.title, detail: task.kind.title, symbol: task.kind.symbol,
                          explainer: "Отмечено по напоминанию из ухода. Само напоминание правится там же — здесь меняется только эта запись.")
        }
        if let id = event.medicationID, let medication = medications.first(where: { $0.id == id }) {
            return Origin(title: medication.name, detail: medication.doseText, symbol: "pills",
                          explainer: "Приём по схеме лечения. Если препарат переименовали, здесь всё равно видно, какой именно отметили.")
        }
        if let id = event.trainingSessionID,
           let session = trainingSessions.first(where: { $0.id == id }) {
            let result = session.attempts > 0 ? "\(session.successes) из \(session.attempts)" : nil
            return Origin(title: "\(session.cue) · \(session.place)", detail: result, symbol: "target",
                          explainer: "След занятия. Само занятие лежит в «Занятиях и шагах» — там его можно и убрать.")
        }
        return nil
    }
}
