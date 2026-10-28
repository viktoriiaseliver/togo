import SwiftUI
import SwiftData

/// Режим дня и питания в профиле. Тот же редактор, что и в онбординге,
/// только сохраняет сразу в собаку.
struct ScheduleScreen: View {
    let dog: Dog

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft = ScheduleDraft()
    @State private var loaded = false

    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            // Плашка была, права не называла — тот же случай, что
            // в `ProfileScreen`, и тем же лечением. «Право на профиль»
            // в списке «Семьи» не значится: там оно зовётся «Менять
            // профиль и уход».
            if !canEdit { ПлашкаПрава(право: .editProfile) }
            ScheduleEditor(draft: $draft)
                .disabled(!canEdit)
        } bottom: {
            if canEdit {
                TGButton(title: "Сохранить") { сохранить() }
            }
        }
        .navigationTitle("Режим")
        .cinemaScreen()
        .task {
            guard !loaded else { return }
            draft = ScheduleDraft.from(dog)
            loaded = true
        }
    }

    /// Сохранить — или вернуть поля и честно сказать «нет».
    ///
    /// **Здесь стоял `apply` без `save()`**, то есть экран рисовал успех
    /// (`Haptics.success`, закрытие), а хранилище о нём ничего не знало:
    /// отказ записи выглядел ровно как удача. Для человека это читается
    /// одним словом — «сбрасывается»: он настроил, вышел, вернулся,
    /// и там прежнее. Отзыв 27.10.2026, 21:54.
    ///
    /// Возвращаются **ровно те поля, что трогает `apply(to:)`**, и
    /// руками, а не `rollback()`: штатный откат SwiftData снимает
    /// признак изменений, но значения не возвращает — разбор
    /// в `ModelContext.persist(otherwise:)`.
    private func сохранить() {
        let былаНорма = dog.dailyNormGrams
        let былаПорция = dog.portionGrams
        let былоКормлений = dog.mealsPerDay
        let былПодъём = dog.wakeMinuteOfDay
        let былОтбой = dog.sleepMinuteOfDay
        let былиЧасы = dog.mealTimes
        // `syncSingleFoodShare()` трогает седьмое поле, и оно в другом
        // объекте. Соседство в вызове — не повод его пропустить.
        let былРасходКорма = dog.stocks.count == 1 ? dog.stocks[0].gramsPerDay : nil

        draft.apply(to: dog)

        guard context.persist(otherwise: {
            dog.dailyNormGrams = былаНорма
            dog.portionGrams = былаПорция
            dog.mealsPerDay = былоКормлений
            dog.wakeMinuteOfDay = былПодъём
            dog.sleepMinuteOfDay = былОтбой
            dog.mealTimes = былиЧасы
            if let былРасходКорма, dog.stocks.count == 1 {
                dog.stocks[0].gramsPerDay = былРасходКорма
            }
        }) else {
            Haptics.warning()
            return
        }
        Haptics.success()
        dismiss()
    }
}
