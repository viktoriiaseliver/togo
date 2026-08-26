import SwiftUI

/// Куда ведёт каждая кнопка. Одно перечисление на весь главный экран —
/// так видно, что путей ровно столько, сколько кнопок.
enum TodayRoute: Identifiable, Hashable {
    case needs
    case walk
    case walkResult
    case stool
    case meal
    case treat
    case incident
    case note
    case training
    case more
    case dayOut
    case edit(UUID)

    var id: String {
        switch self {
        case .edit(let id): "edit-\(id)"
        default: String(describing: self)
        }
    }
}

/// Кнопок в сетке всегда четыре или пять, пятая — «Ещё».
/// Главное действие одно и оно охряное.
struct ActionGrid: View {
    let portionGrams: Int
    let isTravelling: Bool
    let canWriteMedical: Bool
    var onSelect: (TodayRoute) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BigAction(title: isTravelling ? "Остановка" : "Просится",
                          systemImage: isTravelling ? "car" : "figure.walk.departure",
                          isPrimary: true) {
                    onSelect(isTravelling ? .walk : .needs)
                }
                BigAction(title: "Гулять", systemImage: "figure.walk", isPrimary: false) {
                    onSelect(.walk)
                }
            }
            HStack(spacing: 10) {
                SmallAction(title: "Стул", systemImage: "leaf") { onSelect(.stool) }
                SmallAction(title: "Еда", subtitle: portionGrams > 0 ? "\(portionGrams) г" : nil,
                            systemImage: "fork.knife") { onSelect(.meal) }
                SmallAction(title: "Инцидент", systemImage: "exclamationmark.triangle") { onSelect(.incident) }
                SmallAction(title: "Ещё", systemImage: "ellipsis") { onSelect(.more) }
            }
        }
        .padding(.horizontal, Token.Spacing.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }
}

struct BigAction: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .textStyle(AppFont.cardTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Token.Ink.primary)
            .padding(.horizontal, Token.Space.s8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .fill(isPrimary ? Token.Action.primary : Token.Surface.sunken)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct SmallAction: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    // Пять плиток в ряд — колонка узкая. Чуть мельче лучше,
                    // чем «Инциде…».
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Token.Ink.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(Token.Ink.primary)
            .frame(maxWidth: .infinity, minHeight: Token.Size.tapTarget + 8)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.tile, style: .continuous)
                    .fill(Token.Surface.sunken)
            )
        }
        .buttonStyle(.plain)
        // Подпись под кнопкой — часть оформления, а не имени: голосом
        // и в тестах кнопка называется ровно так, как её зовут люди.
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }
}

