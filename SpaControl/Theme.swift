import SwiftUI

extension Color {
    /// Init from a 0xRRGGBB literal — keeps the palette readable and matched to
    /// the design mockup.
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >>  8) & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255
        )
    }
}

/// Shared palette for the (dark-only) app, from the design mockup.
enum Theme {
    static let water = Color(hex: 0x40D4E2)   // cool water / interactive
    static let heat  = Color(hex: 0xFF9F45)   // heat / temperature / target
    static let good  = Color(hex: 0x3ED67F)   // semantic: connected / ok
    static let stale = Color(hex: 0xFFC24B)   // semantic: stale feed
    static let fault = Color(hex: 0xFF5A5F)   // semantic: fault
    static let muted = Color(hex: 0x8CA1B4)   // secondary text

    // Card background matches the existing dashboard cards so the ported dial
    // blends with the not-yet-restyled views.
    static let card     = Color(red: 0.14, green: 0.20, blue: 0.28)
    static let screenBg = Color(red: 0.10, green: 0.15, blue: 0.22)
    static let track    = Color.white.opacity(0.08)
}
