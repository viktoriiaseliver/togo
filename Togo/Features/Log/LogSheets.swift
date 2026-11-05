import SwiftUI
import UIKit
import SwiftData
import PhotosUI

/// Универсальная шторка на числовую запись: еда, вода, лакомство.
struct QuantitySheet: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let unit: LocalizedStringKey
    let step: Int
    let range: ClosedRange<Int>
    var explainer: LocalizedStringKey?
    var onSave: (Int) -> Void

    /// Начальное значение приходит снаружи, но живёт как состояние.
    /// Просто `@State var amount: Int` с присваиванием из параметра —
    /// смелл: SwiftUI обновит его только при первом создании, и это
    /// поведение легко принять за ошибку.
    @State private var amount: Int

    @Environment(\.dismiss) private var dismiss

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey?,
        unit: LocalizedStringKey,
        step: Int,
        range: ClosedRange<Int>,
        amount: Int,
        explainer: LocalizedStringKey? = nil,
        onSave: @escaping (Int) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.unit = unit
        self.step = step
        self.range = range
        self.explainer = explainer
        self.onSave = onSave
        _amount = State(initialValue: amount)
    }

    var body: some View {
        TGSheet(title: title, subtitle: subtitle) {
            TGCard {
                TGStepper(value: $amount, unit: unit, step: step, range: range)
            }
            if let explainer { TGExplainer(text: explainer) }
        } footer: {
            TGButton(title: "Записать") {
                onSave(amount)
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }
}

struct MealSheet: View {
    let dog: Dog?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        QuantitySheet(
            title: "Еда",
            subtitle: (dog?.foodBrand.isEmpty == false ? dog?.foodBrand : nil).map { LocalizedStringKey.готовая($0) },
            unit: "граммов",
            step: 5,
            range: 0...600,
            // Запасного «60» тут больше нет: оно подставлялось собаке,
            // у которой нормы нет вовсе, и выглядело её порцией.
            // Ноль в шаговике — это не утверждение: человек всё равно
            // крутит его сам, и крученое им и есть подтверждение.
            amount: dog?.servingGrams ?? 0,
            explainer: (dog?.servingGrams ?? 0) > 0
                ? "Порция подставлена из профиля: жать нужно один раз, граммы уже подписаны."
                : "Порцию подставить не из чего: дневная норма не записана. Накрути сколько положил — или запиши норму в режиме питания, и дальше она будет подставляться сама."
        ) { grams in
            EventLog(context: context, appState: appState)
                .record(.meal, dog: dog, confirmation: "Записано · Еда \(grams) г") { event in
                    event.grams = grams
                    event.note = dog?.foodBrand.isEmpty == false ? dog?.foodBrand : nil
                }
        }
    }
}

struct TreatSheet: View {
    let dog: Dog?
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    var body: some View {
        QuantitySheet(
            title: "Лакомство",
            subtitle: (dog?.rewards.isEmpty == false ? dog?.rewards.joined(separator: " · ") : nil)
                .map { LocalizedStringKey.готовая($0) },
            unit: "граммов",
            step: 1,
            range: 0...200,
            amount: 5,
            explainer: "Лимита на лакомства нет. Есть дневная норма, часть которой собака зарабатывает, — это и снимает конфликт между занятиями и весом."
        ) { grams in
            EventLog(context: context, appState: appState)
                .record(.treat, dog: dog, confirmation: "Записано · Лакомство \(grams) г") { event in
                    event.grams = grams
                    event.fromPortion = dog?.trainingFoodFromPortion ?? true
                }
        }
    }
}

/// Снять момент — фотография, которая уедет в запись дневника.
///
/// **Решение Виктории 27.10.2026: «фото момента (мы добавили
/// возможность фоткать же)».** Возможность была у ДОКУМЕНТОВ
/// (`DogDocument.image` с 08.10), у записи дневника её не было:
/// снять стул, чтобы показать врачу через неделю, было нечем.
///
/// # Почему общий блок, а не кнопка в каждой шторке
///
/// Вид нужен в двух местах — у стула и у инцидента, — и в обоих
/// он один и тот же: выбрать, ужать, показать миниатюру, дать
/// убрать. Две копии этого разошлись бы молча: в Togo уже
/// заплачено тремя реализациями «не кормить», из которых молчали
/// две.
///
/// # Сжатие берётся готовое, а не пишется второе
///
/// `DocumentPhoto.shrink` — та самая дорога, у которой в голове
/// записан разбор про `UIGraphicsImageRenderer` и масштаб устройства
/// (запрошенные 1600 превращались в 4800, вес — в девять раз).
/// Второй такой же код завёл бы второй дом у правила «сколько весит
/// снимок в базе».
///
/// > **Снимок с камеры в базе — это мегабайты в каждом запросе
/// > ленты.** Поэтому и `shrink`, и `.externalStorage` у поля:
/// > файл лежит рядом, в строке таблицы только ссылка.
struct ФотоМомента: View {
    @Binding var data: Data?

    @State private var picked: PhotosPickerItem?

    var body: some View {
        TGCard {
            TGSectionHeader(title: "фото",
                            subtitle: "если надо показать врачу")
            if let data, let image = КэшСнимков.картинка(data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // 3:4 — та же пропорция, что у снимков документов
                    // (ответ дизайна, круг 5 п. 6). Одно число на два
                    // места, а не два похожих.
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Token.Radius.tile,
                                                style: .continuous))
                    .accessibilityLabel("Фото момента")
                TGButton(title: "Убрать фото", variant: .secondary, size: .medium) {
                    self.data = nil
                }
            } else {
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    TGIconRow(symbol: "camera",
                              title: "Снять или выбрать",
                              detail: "останется в дневнике и в сводке врачу")
                        .frame(minHeight: Token.Size.tapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                // Полноразмерный снимок — десятки мегабайт. В дневнике
                // он не нужен: врач смотрит на вид, а не на текстуру.
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let shrunk = await DocumentPhoto.shrinkВФоне(raw)
                else { picked = nil; return }
                data = shrunk
                picked = nil
            }
        }
    }
}
