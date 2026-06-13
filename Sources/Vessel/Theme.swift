import SwiftUI

public struct AppTheme {
    // Main layout
    public static let sidebarBackground = Color(red: 244/255, green: 234/255, blue: 213/255) // #F4EAD5
    public static let mainBackgroundTop = Color(red: 248/255, green: 241/255, blue: 225/255) // #F8F1E1
    public static let mainBackgroundBottom = Color(red: 240/255, green: 230/255, blue: 208/255) // #F0E6D0
    
    public static let mainBackgroundGradient = LinearGradient(
        colors: [mainBackgroundTop, mainBackgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Cards
    public static let cardBackground = Color.white.opacity(0.8)
    public static let cardBorder = Color(red: 222/255, green: 206/255, blue: 175/255) // #DECEAF
    
    // Accents
    public static let accentBlue = Color(red: 43/255, green: 60/255, blue: 219/255) // #2B3CDB
    public static let buttonBlue = Color(red: 43/255, green: 60/255, blue: 219/255)
    
    // Texts
    public static let textPrimary = Color(red: 30/255, green: 30/255, blue: 30/255)
    public static let textSecondary = Color(red: 110/255, green: 110/255, blue: 110/255)
    
    // Status
    public static let runningGreen = Color(red: 16/255, green: 185/255, blue: 129/255)
    public static let stoppedRed = Color(red: 239/255, green: 68/255, blue: 68/255)
    
    // Terminal
    public static let darkTerminalBackground = Color(red: 80/255, green: 80/255, blue: 80/255)
}
