import SwiftUI

/// Иллюстрация «линия» из пакета дизайна окт 2026. Два слоя-шаблона,
/// цвет берётся у токенов на отрисовке.
///
/// **Почему два слоя, а не готовая картинка.** У рисунка ровно два
/// цвета — контур `--text-secondary` и деталь `--accent` (ошейник
/// и предмет). Запечённый цвет означал бы по картинке на каждую
/// комбинацию: акцент стал ПЕРЕКЛЮЧАЕМЫМ (Indigo · Orange · Pink,
/// см. `AccentChoice`), тем четыре (Dark, Light, Dark HC, Light HC) —
/// это 8 сцен × 3 × 4 = 96 файлов и ручная пересборка при любой правке
/// палитры. Шаблон красится токеном и следует за ним сам; смена
/// акцента стоит ноль файлов.
///
/// Слои собирает `Tools/иллюстрации.py` из
/// `Togo/Resources/Иллюстрации-источник/*.svg`. Источник правды —
/// эти восемь файлов, а не каталог ассетов: каталог производный
/// и пересобирается командой.
///
/// **Чего эта вью не делает.** Она не решает, какая сцена к какому
/// экрану: это продуктовое решение, и оно в `Scene` рядом с местом
/// применения. И не ставит подпись: по правилу дизайна «рядом
/// с иллюстрацией следы и жетон не ставятся», а текст — дело экрана.
struct TGIllustration: View {

    /// Восемь сцен пакета. Список закрыт: новая сцена — решение,
    /// а не находка в каталоге.
    enum Scene: String, CaseIterable {
        case feed        // кормление
        case treat       // лакомство, лечение
        case family      // общий дневник
        case offline     // нет сети
        case history     // пустая история
        case stock       // запас
        case onboarding  // первый запуск
        case paywall     // Pro
    }

    let scene: Scene

    /// Цвет контура. По умолчанию — приглушённые чернила: ровно то,
    /// чем задан `stroke` в источнике (`--text-secondary` = `#B2B2AE`,
    /// то же значение, что `Token.Ink.secondary`).
    var line: Color = Token.Ink.secondary

    /// Цвет детали. По умолчанию — акцент приложения.
    var accent: Color = Token.Action.primary

    /// Высота. Пропорции рисунка 240×160, то есть 3:2, и ширина
    /// считается от высоты — иначе на узком экране рисунок обрежется
    /// по бокам молча.
    var height: CGFloat = 160

    var body: some View {
        ZStack {
            layer("ill-\(scene.rawValue)-line", tint: line)
            layer("ill-\(scene.rawValue)-accent", tint: accent)
        }
        .frame(width: height * 1.5, height: height)
        // Иллюстрация ничего не сообщает сверх текста рядом. Оставить
        // её видимой для VoiceOver значило бы заставить человека
        // слушать имя файла.
        .accessibilityHidden(true)
    }

    private func layer(_ name: String, tint: Color) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(tint)
    }
}

#if DEBUG
#Preview("Все восемь сцен") {
    ScrollView {
        LazyVGrid(columns: [GridItem(), GridItem()], spacing: 24) {
            ForEach(TGIllustration.Scene.allCases, id: \.self) { scene in
                VStack(spacing: 8) {
                    TGIllustration(scene: scene, height: 110)
                    Text(scene.rawValue).font(.caption)
                }
            }
        }
        .padding()
    }
}
#endif
