import SwiftUI

/// Шапка главного экрана: кто эта собака и кто сегодня дежурит.
///
/// Вынесена из `TodayScreen` 28.09. Там она жила приватным свойством
/// среди восьмисот строк вместе с лентой, планом дня, восемью шторками
/// и отметкой дозы — и не могла быть ни показана в галерее, ни собрана
/// в превью: чтобы построить её, надо было построить весь экран
/// с `@Query`, `AppState` и хранилищем.
///
/// **Вход теперь явный.** Это и есть цена, которую платят за вью
/// внутри вью: у Togo уже записано, что поверхность, которую нельзя
/// снять кадром, никто не проверял, — и лечится она входом, а не
/// взглядом.
struct TodayHeader: View {
    let dog: Dog?
    /// Кто дежурит. Пусто — значит дежурство не назначено, а не
    /// «никого нет дома».
    let duty: FamilyMember?
    /// Какой день показан. Пусто — экран без переключателя (так его
    /// зовут там, где день выбирать нечем).
    var день: ScreenDay?
    var листать: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s8) {
            строкаСобаки
            if let день { переключатель(день) }
        }
    }

    private var строкаСобаки: some View {
        HStack(spacing: 12) {
            DogAvatar(dog: dog)
            VStack(alignment: .leading, spacing: 2) {
                Text(dog?.name ?? "Собака")
                    .textStyle(AppFont.cardTitle)
                    .foregroundStyle(Token.Ink.primary)
                // В шапке — только то, что не меняется в течение дня.
                // «Давно ли гуляли» переехало в героя: это ответ
                // на главный вопрос, и мелкой строкой рядом с весом
                // он не читался.
                Text(identityLine)
                    .textStyle(AppFont.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Token.Space.s8)
            // Имя дежурного стоит строкой слева: подпись справа
            // повторяла его слово в слово.
            if let duty {
                TGAvatar(initial: duty.initial, tint: Token.Action.doneQuiet)
            }
        }
        .padding(.top, 4)
    }

    /// Листалка дня: «‹ вчера, 27 сентября ›».
    ///
    /// Вперёд дальше сегодня нельзя, и кнопка не просто серая —
    /// она **исчезает из голоса** (`accessibilityHidden`) вместо того,
    /// чтобы читаться «кнопка, недоступно». Слепой человек не должен
    /// упираться в орган управления, которого для него нет.
    ///
    /// Направление несут и стрелка, и слово: «вчера», «27 сентября».
    /// У Togo записано, что глиф для речи — то же, что цвет для зрения,
    /// и починка в одной модальности выглядит законченной, не будучи ею.
    private func переключатель(_ день: ScreenDay) -> some View {
        HStack(spacing: Token.Space.s8) {
            кнопка(-1, "chevron.left", подпись: "Предыдущий день", включена: true)
            Text(названиеДня(день))
                .textStyle(AppFont.caption)
                .foregroundStyle(день.этоСегодня ? Token.Ink.secondary : Token.Ink.primary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            кнопка(+1, "chevron.right", подпись: "Следующий день", включена: день.можноВперёд)
        }
        .frame(minHeight: Token.Size.tapTarget)
    }

    /// Недоступной стрелки нет вовсе — вместо неё пустое место того же
    /// размера, чтобы дата не прыгала.
    ///
    /// **Серую кнопку рисовать не стал нарочно.** Токена «выключено»
    /// в палитре нет, и подобрать его на глаз значило бы завести
    /// одиннадцатый цвет мимо `tokens.json`. А по сути выключенная
    /// стрелка «вперёд» на сегодняшнем дне не сообщает ничего: вперёд
    /// не бывает, потому что будущего в дневнике нет. Это не временно
    /// недоступное действие, а несуществующее.
    @ViewBuilder
    private func кнопка(_ шаг: Int, _ символ: String,
                        подпись: LocalizedStringKey, включена: Bool) -> some View {
        if включена {
            Button { листать(шаг) } label: {
                Image(systemName: символ)
                    .font(.system(size: Token.Size.iconSm, weight: .semibold))
                    .foregroundStyle(Token.Ink.primary)
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(подпись)
        } else {
            Color.clear
                .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                .accessibilityHidden(true)
        }
    }

    /// «Сегодня» и «вчера» словом, дальше — датой. Человек думает
    /// именно так, а «27 сентября» вместо «вчера» заставляет считать.
    private func названиеДня(_ день: ScreenDay) -> String {
        if день.этоСегодня { return String(localized: "сегодня") }
        let вчера = день.calendar.date(byAdding: .day, value: -1,
                                       to: день.calendar.startOfDay(for: день.сейчас))
        if let вчера, день.calendar.isDate(день.начало, inSameDayAs: вчера) {
            return String(localized: "вчера") + " · " + Fmt.shortDay(день.начало)
        }
        return Fmt.shortDay(день.начало)
    }

    /// Вес и дежурный: две вещи, которые за день не меняются.
    var identityLine: String {
        let weight = dog.map { Fmt.weight($0.weightKg) } ?? "—"
        guard let duty else { return weight }
        return weight + " · дежурит " + duty.name
    }
}

/// Аватар собаки — тот же `TGAvatar`, только крупнее и в тёплой заливке.
struct DogAvatar: View {
    let dog: Dog?

    var body: some View {
        TGAvatar(
            initial: dog?.initial ?? "?",
            image: dog?.photo,
            size: Token.Size.avatarMd,
            tint: Token.Action.doneQuiet
        )
    }
}
