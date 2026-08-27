import SwiftUI

/// Figma: `CheckRow`. Строка плана дня: круг слева, текст справа.
///
/// Из прототипа v2: **отмечает только круг**, тап по тексту открывает
/// запись. Так устроены «Напоминания», и это не вкусовщина — у строки
/// два разных исхода, и они не должны зависеть от того, куда именно
/// попал палец.
///
/// Раньше отметка жила на свайпе вправо, а подпись «свайп вправо =
/// сделано» стояла рядом заголовком. Жест без кнопочного дубля —
/// известная беда: его не видно, ему нельзя научить голосом и его
/// не находят те, ради кого это приложение и написано.
struct TGCheckRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// Отмечено.
    var isDone: Bool
    /// Закрыто до времени: круг с часами вместо галочки, нажатие
    /// объясняет, чего ждём.
    var isLocked: Bool = false
    /// Красит подпись: просрочка — жёлтым, опасное — красным.
    var subtitleTint: Color?
    var onCheck: () -> Void
    var onOpen: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Token.Space.s12) {
            checkbox
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textStyle(AppFont.bodyEmphasis)
                        .foregroundStyle(isDone ? Token.Ink.secondary : Token.Ink.primary)
                        .strikethrough(isDone, color: Token.Ink.faint)
                        .wraps()
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(AppFont.caption.color(subtitleTint ?? Token.Ink.secondary))
                            .wraps()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть запись")

            trailing
        }
        .padding(.vertical, Token.Space.s14)
        .frame(minHeight: Token.Size.tapTarget)
    }

    private var checkbox: some View {
        Button(action: onCheck) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                if isLocked {
                    Image(systemName: "clock")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Token.Ink.secondary)
                } else if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Token.Action.primary)
                }
            }
            // Пустой круг — тонкое кольцо, а не заливка: он должен
            // читаться местом для галочки, а не кнопкой-действием.
            .overlay {
                if !isDone && !isLocked {
                    Circle().stroke(Token.Ink.faint, lineWidth: 1.5)
                        .frame(width: Token.Size.tapTarget, height: Token.Size.tapTarget)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Снять отметку · \(title)" : "Отметить · \(title)")
        .accessibilityAddTraits(isDone ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if isLocked { return Token.Surface.sunken }
        return isDone ? Token.Action.primaryQuiet : .clear
    }
}

extension TGCheckRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, isDone: Bool,
         isLocked: Bool = false, subtitleTint: Color? = nil,
         onCheck: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isDone: isDone,
                  isLocked: isLocked, subtitleTint: subtitleTint,
                  onCheck: onCheck, onOpen: onOpen) { EmptyView() }
    }
}
