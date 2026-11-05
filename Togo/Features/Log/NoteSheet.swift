import SwiftUI
import UIKit
import SwiftData
import PhotosUI

struct NoteSheet: View {
    let dog: Dog?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var text = ""

    var body: some View {
        TGSheet(title: "Заметка", subtitle: "то, что не попадает ни в одну кнопку",
                hasUnsavedChanges: !text.trimmingCharacters(in: .whitespaces).isEmpty) {
            TGCard {
                TextEditor(text: $text)
                    .textStyle(AppFont.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }
        } footer: {
            // Правило круга 5, п. 1: выключенная кнопка обязана
            // сказать, чего не хватает.
            //
            // **И тут же названо расхождение, которое я НЕ чиню:**
            // ворота кнопки режут `.whitespacesAndNewlines`, а
            // `hasUnsavedChanges` выше (`:261`) — только
            // `.whitespaces`. Заметка из одного перевода строки даёт
            // «есть несохранённое» при выключенной кнопке. Величина
            // одна, предикатов два; свести их — правка поведения
            // закрытия листа, названа открытым пунктом, а строка
            // ниже стоит на той величине, что в воротах.
            VStack(spacing: Token.Space.s8) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Напиши заметку — пустую записывать нечего")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
                TGButton(title: "Записать",
                         isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                EventLog(context: context, appState: appState)
                    .record(.note, dog: dog, confirmation: "Записано · Заметка") { event in
                        event.note = text
                    }
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
