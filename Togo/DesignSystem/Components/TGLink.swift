import SwiftUI

/// Figma: `NavigationRow`. Строка списка, ведущая на другой экран.
///
/// Появилась после рефакторинг-чека: связка
/// `NavigationLink { … } label: { TGListRow(…) }.buttonStyle(.plain)`
/// была скопирована в двух десятках мест. Копии расходились —
/// где-то забывался `.buttonStyle(.plain)`, и строка красилась в синий,
/// ломая палитру, в которой синего нет вовсе.
struct TGLink<Destination: View>: View {
    let title: String
    var value: String?
    var systemImage: String?
    var tone: Color = Token.Ink.primary
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            TGListRow(title: title, value: value, systemImage: systemImage, tone: tone)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Текст переносится по словам и не жмётся в одну строку.
    ///
    /// `fixedSize(horizontal: false, vertical: true)` встречался в коде
    /// три десятка раз и каждый раз требовал вспомнить, что он делает.
    func wraps() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
