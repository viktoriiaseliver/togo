import SwiftUI

/// Шапка-плакат: цветная полоса под статус-баром с названием экрана
/// и подзаголовком. Решение дизайна окт 2026 (`DECISIONS.md`, «Плакат
/// применяется на всех экранах чистовика») дословно:
///
/// > формы, списки, онбординг, профиль, настройки — **шапка-плакат**
/// > (статус-бар, навигация, заголовок 40 Rounded, подзаголовок) цветом
/// > `--poster-bg`, контент ниже на обычном фоне. **Шторки и системные
/// > поверхности без плаката.**
///
/// **Это НЕ `TGPoster`.** Тот — блок состояния «Сегодня» и «На улице»:
/// пять режимов, показание, прогресс, цвет по `PosterMode`. Этот —
/// полоса с названием, и режима у неё нет вовсе.
///
/// **Почему без `PosterMode`.** Решение называет один токен — `--poster-bg`,
/// — а не правило «цвет по состоянию». Шапка формы не несёт состояния
/// дня: «Настройки» не бывают натощак. Поэтому ни ветки здесь,
/// ни правки `PosterMode` не нужно, и сам `PosterMode` эта шапка
/// не спрашивает.
///
/// Совпадение с `TGPoster` в режиме `.usual` (оба синие) — совпадение,
/// а не связь: если режим `.usual` когда-нибудь поменяет цвет, шапка
/// за ним **не идёт**, потому что решение привязало её к `--poster-bg`
/// напрямую. Не «унифицировать».
///
/// **Текст берёт семью «на цветном».** У плаката три семьи текста,
/// и у токенов это написано прямо: `label` честен ТОЛЬКО на нейтральном
/// блоке, на синем в светлой он даёт 3,15, а `caption` — 1,10. Блок
/// шапки цветной всегда, поэтому здесь `labelOnColor` и `captionOnColor`.
/// Приёмка — замер пикселя на кадре, а не это рассуждение.
struct TGPosterHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s4) {
            Text(title)
                .textStyle(AppFont.posterHeaderTitle)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .textStyle(AppFont.posterHeaderSubtitle)
                    .wraps()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.bottom, Token.Space.s16)
        .background(Token.Poster.background)
    }
}

extension View {

    /// Надеть шапку-плаката на экран.
    ///
    /// **Применяется к ЭКРАНУ, а не к шторке** — и это не оговорка,
    /// а то, на чём правило ломается. Замер 07.10.2026: `WhatsNewScreen`
    /// показывается **обоими** способами — шторкой из `TogoApp`
    /// и переходом из настроек.
    ///
    /// > «Экран» и «шторка» — свойства ПОКАЗА, а не вью.
    ///
    /// Поэтому шапка не выводится из каркаса (`TGScreen` против
    /// `TGSheet`): `PaywallScreen` собран на `TGScreen` и показывается
    /// шторкой во всех трёх местах — повесь шапку на каркас, и плакат
    /// окажется ровно там, где решение дизайна его запрещает.
    ///
    /// Двойной вид разводится **явным параметром** на месте показа,
    /// а не окружением. Окружение сняло бы шапку молча везде, где её
    /// забыли, — то есть прятало бы ошибку; явный параметр виден
    /// в коде, и таких мест сегодня **одно**.
    ///
    /// Системный большой заголовок при этом гасится: два заголовка
    /// подряд — это не «плакат плюс навигация», это просто два
    /// заголовка.
    func posterHeader(_ title: LocalizedStringKey,
                      subtitle: LocalizedStringKey? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            // Титул в баре гасится, а `navigationTitle` остаётся.
            //
            // Иначе название экрана выводится ДВАЖДЫ: мелким в панели
            // и крупным в плакате. Решение дизайна описывает шапку как
            // несущую и статус-бар, и навигацию, то есть титул живёт
            // в плакате, а не в баре.
            //
            // Снять сам `navigationTitle` нельзя: по нему подписана
            // кнопка «назад» на дочерних экранах и им экран называет
            // себя VoiceOver. Поэтому гасится ПОКАЗ, а не значение.
            //
            // **Не проверено кадром.** Что пустой `principal` правда
            // убирает титул и не оставляет дыры в баре — утверждение
            // о показе, а такие у нас принимает только кадр
            // на симуляторе. `ImageRenderer` системную панель
            // не рисует, и эта строка держится на чтении документации,
            // а не на замере. До кадра шапку дальше одного экрана
            // не раскатываю.
            .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
            .safeAreaInset(edge: .top, spacing: 0) {
                TGPosterHeader(title: title, subtitle: subtitle)
            }
            .toolbarBackground(Token.Poster.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

#if DEBUG
#Preview("Шапка-плакат") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Spacing.stack) {
                TGCard {
                    Text("Контент ниже — на обычном фоне")
                        .textStyle(AppFont.cardTitle)
                }
            }
            .padding(.horizontal, Token.Spacing.screenPadding)
        }
        .themeSurface(.screen)
        .posterHeader("Настройки", subtitle: "Язык, уведомления, перенос")
    }
}
#endif
