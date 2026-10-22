import SwiftUI

/// Низ «Сегодня»: главная кнопка по состоянию, вторая и круглая «+».
///
/// Решение Виктории 22.10.2026, источник — `design_handoff_togo_ios28`,
/// «Навигация (решено)»; геометрия и состав сняты с кадров
/// `screenshots/01.png` и `02.png`.
///
/// ```
/// кадр 01, обычный день   «Просится» БЕЛАЯ с лапой · «Гулять» тёмная · +
/// кадр 02, время дозы     «Дал» СИНЯЯ · «Беру на себя» тёмная · +
/// ```
///
/// **Цвет главной кнопки берёт ТОН, а не стоит безусловно** — решение
/// Виктории 22.10.2026 («Кино» заменяет Graphite целиком): белая
/// с текстом `#111` это **обычное** состояние, а у дозы кнопка синяя,
/// у тревоги терракотовая. Прибить белую безусловно значило бы отнять
/// цвет у дозы и тревоги, то есть у единственных двух состояний,
/// ради которых экран вообще красится.
struct TodayBottomBar: View {
    let tone: ReadingTone
    /// Главная кнопка: что делать прямо сейчас.
    let главная: Действие
    /// Вторая кнопка. На кадрах она есть всегда, но состояние без
    /// второго пути возможно — тогда её нет, а «+» остаётся.
    var вторая: Действие?
    /// Круглая «+» — шторка «Записать».
    let записать: () -> Void

    @Environment(\.dynamicTypeSize) private var размерТекста

    struct Действие {
        let название: LocalizedStringKey
        let символ: String
        let действие: () -> Void
    }

    // `size.buttonPrimary = 60`, `size.plus = 60` — токенов с такими
    // именами в проекте ещё нет, их заводит другой агент. Названо
    // в отчёте.
    private let высотаКнопки: CGFloat = 60

    var body: some View {
        // Раскладка выбирается явным `if`, а не `ViewThatFits`:
        // он запрещён в проекте — держал в дереве обе раскладки,
        // и озвучка находила две кнопки «Отменить».
        //
        // На крупном системном кегле три органа в строку не помещаются
        // ПО УСТРОЙСТВУ: «Беру на себя» уже на обычном кегле уходит
        // в две строки (кадр 02). Тогда столбцом — места вдвое больше,
        // порядок чтения тот же.
        Group {
            if размерТекста.isAccessibilitySize {
                VStack(spacing: Token.Space.s10) {
                    кнопка(главная, главнаяЛи: true)
                    if let вторая { кнопка(вторая, главнаяЛи: false) }
                    плюс
                }
            } else {
                HStack(spacing: Token.Space.s10) {
                    кнопка(главная, главнаяЛи: true)
                    if let вторая { кнопка(вторая, главнаяЛи: false) }
                    плюс
                }
            }
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, Token.Space.s10)
        .padding(.bottom, Token.Space.s6)
    }

    /// Обе кнопки одинаковые: высота 60, `flex 1/1`, 17 semibold.
    /// Так сказано в хендоффе, и на кадрах они правда одной ширины.
    private func кнопка(_ д: Действие, главнаяЛи: Bool) -> some View {
        Button(action: д.действие) {
            HStack(spacing: Token.Space.s8) {
                Image(systemName: д.символ)
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .accessibilityHidden(true)
                // Цвет подписи задаётся здесь, а не наследуется: стиль
                // несёт собственные чернила и красит сам `Text`, то есть
                // побеждает `.foregroundStyle` предка. Внешний цвет
                // стоял верный и молча перекрывался — подпись оставалась
                // светлой на светлой заливке. Это уже оплачено
                // в `ActionGrid`.
                Text(д.название)
                    .textStyle(AppFont.bodyEmphasis, color: чернила(главнаяЛи))
                    // Обрезать подпись главного действия нельзя ни при
                    // какой настройке: «Просит…» на главной кнопке
                    // приложения — кадр 28.09.
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
            }
            .foregroundStyle(чернила(главнаяЛи))
            .padding(.horizontal, Token.Space.s8)
            .frame(maxWidth: .infinity, minHeight: высотаКнопки)
            .background(заливка(главнаяЛи),
                        in: RoundedRectangle(cornerRadius: Token.Radius.control,
                                             style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(д.название))
    }

    /// Круглая «+» — ровно 60, и это цель касания с запасом.
    private var плюс: some View {
        Button(action: записать) {
            Image(systemName: "plus")
                .font(.system(size: Token.Size.iconMd, weight: .semibold))
                .foregroundStyle(Token.Ink.primary)
                .frame(width: высотаКнопки, height: высотаКнопки)
                .background(Token.Surface.card, in: Circle())
        }
        .buttonStyle(.plain)
        // Голосом — словом, а не «плюс»: человек слышит, ЧТО кнопка
        // делает, а не как она нарисована.
        .accessibilityLabel("Записать")
        .accessibilityIdentifier("низ-записать")
    }

    /// Заливка главной кнопки — у тона; второй — всегда тихая.
    private func заливка(_ главнаяЛи: Bool) -> Color {
        guard главнаяЛи else { return Token.Surface.card }
        switch tone {
        case .dose: return Token.Action.primary
        case .alarm: return Token.Status.overdueText
        // Белая с текстом #111 — обычное состояние, ночь, натощак, выход.
        case .normal, .fasting, .night, .walk: return Token.Ink.onAccent
        }
    }

    private func чернила(_ главнаяЛи: Bool) -> Color {
        guard главнаяЛи else { return Token.Ink.primary }
        return tone.tintsPrimaryButton ? Token.Ink.onAccent : Token.Surface.screen
    }
}

/// Шторка «Записать» — то, что открывает круглая «+».
///
/// Состав снят с кадра `screenshots/06.png` и сверен с прототипом
/// (`openRecord`, `Togo-RU.dc.html:587`) — они совпали дословно:
///
/// ```
/// Инцидент   красным   «рвота, лужа, съел с земли»
/// Стул                 без подписи
/// Еда                  «65 г» — размер порции этой собаки
/// Ещё       многоточие «лакомство, занятие, заметка, вес»
/// ```
///
/// **Инцидент первым и красным.** Это не вкус: когда он нужен, его
/// ищут в панике, и искать его в списке по алфавиту некогда. Тот же
/// довод, по которому «Если что-то случилось» стоит первым блоком
/// во вкладке собаки.
struct RecordSheet: View {
    /// Размер порции — подпись у «Еды». Ноль значит «не считаем»,
    /// и тогда подписи нет: «0 г» читается поломкой, а не фактом.
    let порцияГрамм: Int
    /// Какой день записываем — «сейчас · 17:54» или дата.
    let подзаголовок: String
    var onSelect: (TodayRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // `closeTitle` — «Отмена», а не умолчательное «Закрыть»:
        // так на кадре 06, и так вернее по смыслу. Шторка ничего
        // не создаёт сама, она выбирает, ЧТО создавать, — «Закрыть»
        // читалось бы как «готово».
        TGSheet(title: "Записать", subtitle: .готовая(подзаголовок),
                closeTitle: "Отмена") {
            TGCard(spacing: 0) {
                строка("Инцидент", "рвота, лужа, съел с земли",
                       "exclamationmark.triangle", тон: Token.Status.overdueText,
                       маршрут: .incident)
                TGDivider()
                строка("Стул", nil, "leaf", тон: Token.Ink.primary, маршрут: .stool)
                TGDivider()
                строка("Еда", порцияГрамм > 0 ? String(localized: "\(порцияГрамм) г") : nil,
                       "fork.knife", тон: Token.Ink.primary, маршрут: .meal)
                TGDivider()
                строка("Ещё", "лакомство, занятие, заметка, вес",
                       "ellipsis", тон: Token.Ink.primary, маршрут: .more)
            }
        }
        .presentationDetents([.medium])
    }

    private func строка(_ название: LocalizedStringKey,
                        _ подпись: String?,
                        _ символ: String,
                        тон: Color,
                        маршрут: TodayRoute) -> some View {
        Button {
            // Закрываем первой, иначе вторая шторка открывается поверх
            // закрывающейся — у Togo это уже записано как известная дыра
            // у пропущенной дозы.
            dismiss()
            onSelect(маршрут)
        } label: {
            TGListRow(title: название,
                      value: подпись.map { .готовая($0) },
                      systemImage: символ,
                      accessory: .none,
                      tone: тон)
        }
        .buttonStyle(.plain)
    }
}
