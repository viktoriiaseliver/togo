import SwiftUI
import UIKit

/// Фото собаки в круге — то, на что смотрят, пока идёт прогулка.
///
/// Кадр 08 хендоффа `design_handoff_togo_ios28`: не пустое кольцо
/// прогресса, а **портрет собаки** с тонкой светлой обводкой. README
/// говорит «кольцо + таймер», и по нему вышло бы кольцо загрузки —
/// кадр показывает другое. Мерено по кадру.
///
/// Прогресса здесь нет намеренно: у прогулки нет назначенной длины,
/// и кольцо, заполняющееся «до нормы», сказало бы, что она есть.
/// В прототипе `pct` считается от 25 минут — числа, которого никто
/// не назначал; переносить его значило бы завести норму молча.
///
/// ## Кнопки камеры здесь нет, и это решение
///
/// На кадре справа внизу у круга стоит круглая кнопка камеры. Входа
/// для неё в продукте **нет**: у `ActiveSession` нет поля под фото
/// (замер 22.10.2026 — `kind`, `startedAt`, `startedBy`, `marks`,
/// `pausedAt`, `pausedTotal`, и всё), и запись прогулки собирается
/// в `finish()` без снимков. Нарисовать кнопку поверх несуществующего
/// механизма — это «вход есть, механизма нет»: человек нажмёт и получит
/// отказ, **и отказ будет нашим, а не его**. Названо в отчёте.
struct WalkRing: View {
    let dog: Dog?

    /// Какую долю ширины занимает портрет. Доля, а не точки: на кадре
    /// круг — 0,46 ширины, и в точках он соврал бы на SE и на iPad.
    private static let доляШирины: CGFloat = 0.46

    var body: some View {
        портрет
            .clipShape(Circle())
            .overlay {
                // Тонкая светлая обводка с кадра: она отделяет портрет
                // от фона-фотографии, иначе тёмная собака на тёмном фоне
                // сливается краем.
                Circle().strokeBorder(Token.Surface.glassEdge,
                                      lineWidth: Token.Size.hairline * 2)
            }
            .containerRelativeFrame(.horizontal) { ширина, _ in
                ширина * Self.доляШирины
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var портрет: some View {
        if let photo = dog?.photo, let image = UIImage(data: photo) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            // Без фото — силуэт, а не пустой круг: пустой круг читается
            // как «не загрузилось».
            ZStack {
                Token.Surface.sunken
                Image(systemName: "pawprint.fill")
                    .font(.system(size: Token.FontSize.display,
                                  weight: Token.FontWeight.light))
                    .foregroundStyle(Token.Ink.silhouette)
            }
        }
    }
}

/// Слайдер «Домой» — им заканчивают прогулку.
///
/// Хендофф, раздел «На улице»: слайдер вместо кнопки. Причина не в моде:
/// прогулку заканчивают **один раз**, а отмечают десять, и «Закончить»
/// рядом с «Пописал» ловила промахи — отзыв «нажатие на один из таймеров
/// закрывает экран» ровно про это. Смахом промахнуться нельзя.
///
/// Ручка слева, белый круг со значком дома — с кадра 08.
struct WalkHomeSlider: View {
    var onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var беДвижения
    @State private var сдвиг: CGFloat = 0
    @State private var сработал = false

    /// Какую долю дорожки надо пройти. Меньше половины — случайный смах
    /// по экрану закончил бы прогулку; больше трёх четвертей — не достать
    /// большим одной рукой, а ровно за этим слайдер и ставили.
    private static let порог: CGFloat = 0.65

    var body: some View {
        GeometryReader { geo in
            let ручка = Token.Size.controlXL
            let ход = max(0, geo.size.width - ручка - Token.Space.s4 * 2)

            ZStack(alignment: .leading) {
                Capsule().fill(Token.Surface.control)

                HStack(spacing: Token.Space.s4) {
                    Spacer(minLength: ручка)
                    Text("Домой")
                        .textStyle(AppFont.cardTitle, color: Token.Ink.primary)
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(Token.Ink.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Token.Space.s12)
                // Подпись гаснет по мере хода: к концу под ручкой её
                // всё равно не видно, а мигание на последних точках
                // читалось бы как сбой.
                .opacity(ход > 0 ? 1 - min(1, сдвиг / ход) * 0.7 : 1)

                ручкаВида
                    .offset(x: сдвиг)
                    .padding(.leading, Token.Space.s4)
                    .gesture(жест(ход: ход))
            }
        }
        .frame(height: Token.Size.capsule)
        // Смах недоступен озвучке и моторике: у слайдера обязан быть
        // второй путь, иначе прогулку нельзя закончить вовсе.
        // Это не дубль кнопки — это тот же механизм другим входом.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Домой")
        .accessibilityHint("Заканчивает прогулку")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { сработать() }
    }

    private var ручкаВида: some View {
        Image(systemName: "house.fill")
            .font(.system(size: Token.Size.iconMd, weight: Token.FontWeight.semibold))
            .foregroundStyle(Token.Ink.onAccent)
            .frame(width: Token.Size.controlXL, height: Token.Size.controlXL)
            .background(Token.Action.primary, in: Circle())
    }

    private func жест(ход: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { значение in
                guard !сработал, ход > 0 else { return }
                сдвиг = min(ход, max(0, значение.translation.width))
            }
            .onEnded { _ in
                guard !сработал, ход > 0 else { return }
                if сдвиг >= ход * Self.порог {
                    сдвиг = ход
                    сработать()
                } else {
                    // Не дошёл — ручка возвращается. Оставить её на месте
                    // значило бы показать наполовину сделанное действие.
                    withAnimation(беДвижения ? nil : .spring(duration: Token.Duration.quick)) {
                        сдвиг = 0
                    }
                }
            }
    }

    /// Один раз за жизнь вида: прогулка заканчивается однажды, и повторный
    /// вызов закрыл бы уже закрытую сессию.
    private func сработать() {
        guard !сработал else { return }
        сработал = true
        Haptics.success()
        onHome()
    }
}
