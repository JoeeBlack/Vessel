import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct AppTheme {
    private static func dynamicColor(
        lightR: CGFloat, lightG: CGFloat, lightB: CGFloat, lightA: CGFloat = 1.0,
        darkR: CGFloat, darkG: CGFloat, darkB: CGFloat, darkA: CGFloat = 1.0
    ) -> Color {
        #if canImport(AppKit)
        let nsColor = NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(calibratedRed: darkR/255.0, green: darkG/255.0, blue: darkB/255.0, alpha: darkA)
            } else {
                return NSColor(calibratedRed: lightR/255.0, green: lightG/255.0, blue: lightB/255.0, alpha: lightA)
            }
        })
        return Color(nsColor: nsColor)
        #else
        return Color(red: lightR/255.0, green: lightG/255.0, blue: lightB/255.0).opacity(lightA)
        #endif
    }

    private static func dynamicWhiteBlack(
        lightWhite: CGFloat, lightA: CGFloat,
        darkWhite: CGFloat, darkA: CGFloat
    ) -> Color {
        #if canImport(AppKit)
        let nsColor = NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(calibratedWhite: darkWhite, alpha: darkA)
            } else {
                return NSColor(calibratedWhite: lightWhite, alpha: lightA)
            }
        })
        return Color(nsColor: nsColor)
        #else
        return Color(white: lightWhite).opacity(lightA)
        #endif
    }

    // Main layout
    public static let sidebarBackground = dynamicColor(
        lightR: 235, lightG: 225, lightB: 210, lightA: 0.85,
        darkR: 45, darkG: 40, darkB: 35, darkA: 0.85
    ) // Liquid Glass Sidebar

    public static let mainBackgroundTop = dynamicColor(
        lightR: 245, lightG: 240, lightB: 230,
        darkR: 35, darkG: 30, darkB: 25
    ) // Lighter beige tint

    public static let mainBackgroundBottom = dynamicColor(
        lightR: 224, lightG: 201, lightB: 166,
        darkR: 25, darkG: 22, darkB: 18
    ) // Sand/Beige tint
    
    public static let mainBackgroundGradient = LinearGradient(
        colors: [mainBackgroundTop, mainBackgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Cards
    public static let cardBackground = dynamicWhiteBlack(
        lightWhite: 1.0, lightA: 0.4,
        darkWhite: 1.0, darkA: 0.05
    ) // High transparency for glass effect

    public static let cardBorder = dynamicWhiteBlack(
        lightWhite: 1.0, lightA: 0.6,
        darkWhite: 1.0, darkA: 0.15
    ) // Frosted glass border
    
    // Accents
    public static let accentBlue = dynamicColor(
        lightR: 80, lightG: 70, lightB: 60,
        darkR: 210, darkG: 195, darkB: 175
    ) // Muted luxury taupe -> Warm Sand

    public static let buttonBlue = dynamicColor(
        lightR: 80, lightG: 70, lightB: 60,
        darkR: 210, darkG: 195, darkB: 175
    )
    
    // Texts
    public static let textPrimary = dynamicColor(
        lightR: 40, lightG: 35, lightB: 30,
        darkR: 240, darkG: 235, darkB: 230
    )

    public static let textSecondary = dynamicColor(
        lightR: 130, lightG: 120, lightB: 110,
        darkR: 170, darkG: 160, darkB: 150
    )
    
    // Status
    public static let runningGreen = dynamicColor(
        lightR: 46, lightG: 204, lightB: 113,
        darkR: 60, darkG: 220, darkB: 130
    ) // Emerald green

    public static let stoppedRed = dynamicColor(
        lightR: 231, lightG: 76, lightB: 60,
        darkR: 250, darkG: 90, darkB: 75
    ) // Alizarin red
    
    // Terminal
    public static let darkTerminalBackground = dynamicWhiteBlack(
        lightWhite: 0.0, lightA: 0.7,
        darkWhite: 0.0, darkA: 0.5
    ) // Dark glass terminal

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
