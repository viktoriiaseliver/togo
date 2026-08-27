import SwiftUI

nonisolated extension Color {
    /// Единственное место, где в приложении разбирается hex.
    /// Сырые значения приходят только из сгенерированных токенов.
    /// `0xRRGGBB` или `0xRRGGBBAA`.
    ///
    /// Прозрачность нужна тёмной теме: вторичный текст, хайрлайны
    /// и тинты в ней заданы не своим цветом, а долей белого поверх
    /// поверхности. Записывать их сплошным хексом значило бы привязать
    /// каждый к той поверхности, над которой его посчитали.
    init(hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let value = hasAlpha ? hex : (hex << 8) | 0xFF
        self.init(
            .sRGB,
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}
