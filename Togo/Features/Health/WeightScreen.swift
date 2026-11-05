import SwiftUI
import SwiftData

/// Вес. Приложение не считает норму само и не ставит целей по проценту:
/// коридор называет врач.
///
/// # Право: `editProfile`, и оно НАЗВАНО ИСТОЧНИКОМ, а не выбрано мной
///
/// **Замер 26.10.2026: прав здесь не было вовсе.** Ни `canEdit`,
/// ни `appState.can(` — при трёх входах (`HealthScreen:527`,
/// `ProfileScreen:116`, `DogTab:411`). Поле ввода, кнопка «Записать»,
/// создание и удаление взвешивания были открыты **наблюдателю
/// и помощнику**, то есть гостю и маме без прав.
///
/// Цена не косметическая, и она записана тут же, у вердикта:
/// **«вес это та величина, от которой считается доза»**. Удалённое
/// взвешивание откатывает `dog.weightKg` к предыдущему замеру
/// (`delete`), а от него считают дозу и коридор.
///
/// **Какое право — ответил сам `Permission`, и это дешевле спора:**
///
/// ```
/// Permission.editProfile.detail   «порция, ВЕС, напоминания, занятия»
///                                 ← вес назван поимённо
/// Permission.editTreatment.detail «препараты, часы, окно натощак»
///                                 ← веса нет
/// ProfileScreen:26                уже гасит .editProfile, а это
///                                 ОДИН ИЗ ТРЁХ входов сюда
/// ```
///
/// То есть у двух входов из трёх ответ уже дан, и дан одинаково.
///
/// **Почему НЕ `editTreatment`, хотя рядом `Prescription.dogWeightKg`
/// стоит под ним.** Это две разные величины одного имени:
/// `dogWeightKg` — вес, ОТ КОТОРОГО считали дозу в тот день, поле
/// медицинского бланка, вводимое задним числом (и нарочно
/// не подставляемое, `PrescriptionEditor:276`). Здесь — текущий вес,
/// бытовой замер, который делает тот, кто держит собаку на весах.
/// `editTreatment` по умолчанию есть **только у владельца**
/// (`defaultPermissions`), и под ним мама-со-владелец не смогла бы
/// записать взвешивание вовсе.
///
/// > **Право выбиралось не по тому, насколько величина важна,
/// > а по тому, кто её производит.** Читают вес все — и чтение
/// > ниже не закрыто ни на строку.
///
/// # Орган, которого роль не даёт, УБРАН, а не выключен
///
/// Ответ дизайна круга 5, п. 2: «органы, которых роль не даёт, гостю
/// не показываются; выключенными их не делаем. Там, где орган можно
/// убрать совсем, правильнее убрать». Карточка «взвесить сейчас» —
/// **чистый ввод**, смотреть в ней нечего, поэтому без права её нет
/// вовсе; отказ при этом назван словом один раз, `ПлашкаПрава`
/// сверху. Карточка текущего веса, цель врача и история остаются:
/// их читают все.
struct WeightScreen: View {
    let dog: Dog?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var newWeight = ""

    /// Фокус поля веса — единственного `.decimalPad` на экране.
    @FocusState private var весВФокусе: Bool

    /// Вес правит тот, кто правит профиль и уход: это бытовой замер,
    /// а не запись из бланка. Разбор — в голове экрана.
    private var canEdit: Bool { appState.can(.editProfile) }

    var body: some View {
        TGScreen {
            CinemaHeader("Вес", надпись: "коридор врача", отступы: false)
            // Плашка — ДО первого отказа, а не после нажатия: ниже
            // пропадают карточка ввода и дорога к удалению, и без
            // слова это читалось бы как «экран недоделан».
            if !canEdit { ПлашкаПрава(право: .editProfile) }
            TGCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(dog.map { Fmt.weight($0.weightKg) } ?? "—").textStyle(AppFont.display)
                    Spacer()
                    // **Три состояния, а не два.** Прежняя редакция
                    // спрашивала `!dog.isWeightInRange` и всё остальное
                    // сваливала в `else` — а предикат отвечает `true`
                    // на ДВА разных состояния: «вес внутри коридора»
                    // и «коридора не существует» (`Dog.swift:497`,
                    // `guard … else { return true }`). У собаки без
                    // назначенного врачом коридора под её весом стояло
                    // зелёное «в норме».
                    //
                    // > **`else` ловил два состояния и говорил о них
                    // > одно.** Утверждение, которого приложение
                    // > сделать не может — и вес это та величина,
                    // > от которой считается доза.
                    //
                    // Предикат не тронут: для ворот он прав. Спрашиваем
                    // `weightVerdict`, и он построен на `LabNorm`, где
                    // правило «нормы нет → так и скажи» уже живёт.
                    //
                    // **Коридора нет — МОЛЧИМ, а не придумываем слово.**
                    // Новый ключ под заморозкой текстов дал бы русскую
                    // строку французу ровно на медицинском экране;
                    // а молчание согласовано с соседней строкой —
                    // «цель … поставил врач» ниже показывается по тем же
                    // двум полям, то есть вердикт и цель появляются
                    // и исчезают вместе. Если решат словом — адрес здесь.
                    if let dog {
                        switch dog.weightVerdict {
                        case .withinRange:
                            Text("в норме").textStyle(AppFont.caption.color(Token.Action.doneText))
                        case .below, .above:
                            Text("вне коридора").textStyle(AppFont.caption.color(Token.Status.waitingText))
                        case .normUnknown, .indeterminate:
                            EmptyView()
                        }
                    }
                }
                if let low = dog?.targetWeightLow, let high = dog?.targetWeightHigh {
                    Text("цель \(Fmt.weight(low)) — \(Fmt.weight(high)) · поставил врач").textStyle(AppFont.caption)
                }
            }

            карточкаВзвешивания

            TGCard {
                TGSectionHeader(title: "история")
                let history = (dog?.weights ?? []).sorted { $0.date > $1.date }.prefix(12)
                if history.isEmpty {
                    TGExplainer(text: "Пока одно значение — то, что ты ввела при добавлении собаки.")
                } else {
                    ForEach(Array(history)) { entry in
                        // История читается всеми, а удаляется по праву:
                        // без права строка остаётся строкой, а не
                        // выключенной кнопкой, ведущей в тишину.
                        Button { if canEdit { removing = entry } } label: {
                            HStack {
                                Text(Fmt.shortDay(entry.date)).textStyle(AppFont.caption)
                                Spacer()
                                Text(Fmt.weight(entry.kg)).textStyle(AppFont.numeric(15))
                            }
                            .frame(minHeight: Token.Size.tapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                    }
                    // Взвешивание — единственное, что нельзя было исправить.
                    // Опечатка «12,4 → 124» оставалась в графике навсегда
                    // и уводила коридор веса вместе с собой.
                    //
                    // Подсказка про удаление — только тому, кто может
                    // удалить: иначе она посылает человека делать то,
                    // чего ему не дадут.
                    if canEdit {
                        TGExplainer(text: "Ошиблась — тапни по строке и удали.")
                    }
                }
            }
        }
        .navigationTitle("Вес")
        .cinemaScreen(экран: .sub("weight"))
        // Выход с цифровой клавиатуры: у `.decimalPad` своей клавиши
        // возврата нет.
        .готовоНадКлавиатурой { весВФокусе = false }
        .confirmationDialog("Удалить взвешивание?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible,
                            presenting: removing) { entry in
            Button("Удалить", role: .destructive) { delete(entry) }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: { entry in
            Text("\(Fmt.shortDay(entry.date)) · \(Fmt.weight(entry.kg)). Из графика и из коридора веса запись тоже уйдёт.")
        }
    }

    /// Карточка «взвесить сейчас» — **чистый ввод, и без права её нет
    /// вовсе**, а не выключенной (ответ дизайна круга 5, п. 2).
    /// Смотреть в ней нечего: текущий вес, цель врача и история стоят
    /// отдельными карточками и открыты всем.
    @ViewBuilder
    private var карточкаВзвешивания: some View {
        if canEdit {
            TGCard {
                TGSectionHeader(title: "взвесить сейчас")
                HStack(spacing: Token.Space.s12) {
                    TextField("4,1", text: $newWeight)
                        .keyboardType(.decimalPad)
                        .focused($весВФокусе)
                        .textStyle(AppFont.numeric(24))
                    Text("кг").textStyle(AppFont.caption)
                    TGButton(title: "Записать", size: .medium, fullWidth: false,
                             isEnabled: parsedWeight != nil) { save() }
                }
                // Правило круга 5, п. 1. Условие и действие здесь
                // смотрят на ОДНУ величину (`parsedWeight` читают оба),
                // — проверено, и это не тот класс, что в запасе корма.
                // Не хватало только слова.
                //
                // Строка говорит про ФОРМАТ, а не про пустоту:
                // выключенной кнопка остаётся и при набранном
                // «4,1 кг» или «4.1.2» — то есть при непустом поле,
                // и вот тогда тишина и непонятна.
                if parsedWeight == nil, !newWeight.isEmpty {
                    Text("Нужно одно число — например 4,1")
                        .textStyle(AppFont.caption.color(Token.Status.overdueText))
                        .wraps()
                }
            }
        }
    }

    /// Удалить взвешивание, вернув текущий вес к предыдущему замеру.
    ///
    /// **Право спрашивается и ЗДЕСЬ, а не только у органа.** Орган
    /// убран показом, и этого мало: `removing` — состояние, которое
    /// живёт дольше одного кадра, а право меняется извне (владелец
    /// снимает его в «Семье», и обмен приносит это на чужой телефон).
    /// Проверка у показа отвечает на «рисовать ли кнопку»,
    /// а у записи — на «можно ли писать», и это разные вопросы.
    private func delete(_ entry: WeightEntry) {
        guard canEdit, let dog else { return }
        // Надгробие вместо `context.delete`: вес — то, от чего считается
        // доза, и расхождение веса между двумя людьми даёт расхождение
        // дозы. Удаление, не доехавшее до второго человека, оставляло
        // ему точку, которой у хозяйки уже нет.
        let откатНадгробия = ОбщееУдаление.удалить(entry)
        // Текущий вес показывается по всему приложению — если удалили
        // последнее взвешивание, он обязан откатиться, а не остаться
        // от только что стёртой записи.
        let былВес = dog.weightKg
        // `dog.weights` уже отсеивает надгробия, то есть эта запись
        // из него выпала строкой выше; фильтр по `persistentModelID`
        // оставлен как есть — он больше не нужен, но и не врёт,
        // а убрать его значило бы связать откат с порядком двух правок.
        let rest = dog.weights.filter { $0.persistentModelID != entry.persistentModelID }
        if let latest = rest.max(by: { $0.date < $1.date }) {
            dog.weightKg = latest.kg
        }
        guard context.persist(otherwise: {
            dog.weightKg = былВес
            откатНадгробия()
        }) else {
            Haptics.warning()
            return appState.showFailure("Взвешивание не удалилось · попробуй ещё раз")
        }
        Haptics.warning()
        removing = nil
    }

    /// Какую запись предлагается удалить.
    @State private var removing: WeightEntry?

    private var parsedWeight: Double? {
        Double(newWeight.replacingOccurrences(of: ",", with: "."))
    }

    /// Записать взвешивание. Право — как у удаления, и по той же
    /// причине: `newWeight` набран раньше, чем право могло исчезнуть.
    private func save() {
        guard canEdit, let dog, let kg = parsedWeight else { return }
        let entry = WeightEntry(kg: kg)
        entry.dog = dog
        context.insert(entry)
        dog.weightKg = kg

        // Взвесили — значит, напоминание «Взвесить» отработало. Просить
        // человека отметить то же самое второй раз незачем.
        let задача = dog.careTasks.first { $0.title == "Взвесить" }
        let былоСделано = задача?.lastDone
        задача?.markDone()

        guard context.persist(otherwise: {
            context.delete(entry)
            задача?.lastDone = былоСделано
        }) else {
            Haptics.warning()
            return appState.showFailure("Вес не записался · попробуй ещё раз")
        }
        newWeight = ""
        Haptics.success()
    }
}
