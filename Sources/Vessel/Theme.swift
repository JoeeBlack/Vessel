import SwiftUI

public struct AppTheme {
    // Main layout
    public static let sidebarBackground = Color(red: 235/255, green: 225/255, blue: 210/255).opacity(0.85) // Liquid Glass Sidebar
    public static let mainBackgroundTop = Color(red: 245/255, green: 240/255, blue: 230/255) // Lighter beige tint
    public static let mainBackgroundBottom = Color(red: 224/255, green: 201/255, blue: 166/255) // #E0C9A6 Sand/Beige
    
    public static let mainBackgroundGradient = LinearGradient(
        colors: [mainBackgroundTop, mainBackgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Cards
    public static let cardBackground = Color.white.opacity(0.4) // High transparency for glass effect
    public static let cardBorder = Color.white.opacity(0.6) // Frosted glass border
    
    // Accents
    public static let accentBlue = Color(red: 80/255, green: 70/255, blue: 60/255) // Muted luxury taupe
    public static let buttonBlue = Color(red: 80/255, green: 70/255, blue: 60/255)
    
    // Texts
    public static let textPrimary = Color(red: 40/255, green: 35/255, blue: 30/255)
    public static let textSecondary = Color(red: 130/255, green: 120/255, blue: 110/255)
    
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
