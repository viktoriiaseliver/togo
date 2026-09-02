import SwiftUI

/// Как экраны попадают в журнал действий.
///
/// Один модификатор вместо пары `onAppear`/`onDisappear` на каждом экране:
/// пары расходятся — где-то забудут закрывающую половину, и всё, что человек
/// сделал дальше, окажется записано на чужой экран.
extension View {
    /// Отметить, что человек стоит на этом экране.
    func usageScreen(_ screen: UsageLog.Screen) -> some View {
        onAppear { UsageLog.entered(screen) }
            .onDisappear { UsageLog.left(screen) }
    }
}
