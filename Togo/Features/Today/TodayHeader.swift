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

    var body: some View {
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
