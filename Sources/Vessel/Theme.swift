import SwiftUI

public struct AppTheme {
    // Main layout
    public static let sidebarBackground = Color(red: 235/255, green: 245/255, blue: 255/255).opacity(0.85) // Liquid Glass Sidebar
    public static let mainBackgroundTop = Color(red: 240/255, green: 248/255, blue: 255/255) // #F0F8FF Alice Blue
    public static let mainBackgroundBottom = Color(red: 224/255, green: 238/255, blue: 250/255) // #E0EEFA Light Steel Blue tint
    
    public static let mainBackgroundGradient = LinearGradient(
        colors: [mainBackgroundTop, mainBackgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Cards
    public static let cardBackground = Color.white.opacity(0.4) // High transparency for glass effect
    public static let cardBorder = Color.white.opacity(0.6) // Frosted glass border
    
    // Accents
    public static let accentBlue = Color(red: 50/255, green: 150/255, blue: 255/255) // Vibrant bright blue
    public static let buttonBlue = Color(red: 50/255, green: 150/255, blue: 255/255)
    
    // Texts
    public static let textPrimary = Color(red: 20/255, green: 40/255, blue: 60/255)
    public static let textSecondary = Color(red: 100/255, green: 120/255, blue: 140/255)
    
    // Status
    public static let runningGreen = Color(red: 46/255, green: 204/255, blue: 113/255) // Emerald green
    public static let stoppedRed = Color(red: 231/255, green: 76/255, blue: 60/255) // Alizarin red
    
    // Terminal
    public static let darkTerminalBackground = Color.black.opacity(0.7) // Dark glass terminal

    // Domains
    public static func color(for domain: VesselDomain) -> Color {
        switch domain {
        case .generic:
            return Color.clear
        case .personal:
            return Color.blue
        case .work:
            return Color.orange
        case .development:
            return Color.green
        case .untrusted:
            return Color.red
        }
    }
}
