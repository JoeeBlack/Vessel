## 2024-05-14 - Initialize Palette Journal
**Learning:** Initializing palette journal for recording critical UX/a11y learnings.
**Action:** Always document significant UX and accessibility insights here.

## 2024-05-14 - Missing Accessibility Labels on Icon-Only Buttons
**Learning:** Found multiple instances of icon-only buttons (`Image(systemName: ...)`) lacking `accessibilityLabel` and `help` modifiers across `ImagesListView.swift` and `CreateContainerView.swift`. This makes the UI completely inaccessible to VoiceOver users and unclear for sighted users unsure of the icon's meaning.
**Action:** Always add `.help("Description")` for tooltips and `.accessibilityLabel("Description")` to ALL icon-only buttons as a standard practice in this design system.

## 2024-06-13 - SwiftUI Accessibility and Tooltips
**Learning:** In SwiftUI for macOS, adding the `.help("text")` modifier to interactive elements like `Button` natively handles both visual tooltips and screen reader accessibility labels, making it an excellent all-in-one UX improvement for icon-only buttons.
**Action:** Always use the `.help()` modifier for icon-only buttons or complex UI components in SwiftUI macOS projects instead of separate `accessibilityLabel` modifiers unless specific screen reader hints are required.
## 2024-06-15 - Implement Liquid Glass Theme
**Learning:** Applying a 'Liquid Glass' UI style in SwiftUI requires chaining `.background(Material.ultraThin)` before the custom semi-transparent color background `Color.opacity()` to achieve the frosted glass look, alongside refining drop shadows (larger radius, lower opacity) for depth.
**Action:** Consistently use SwiftUI Materials (`.ultraThinMaterial`, `.thinMaterial`) coupled with translucent background colors and soft gradients when implementing glassmorphism across components.

## 2026-06-17 - Custom SwiftUI Views in Menu Bar
**Learning:** By default, `MenuBarExtra` renders its content as a standard macOS menu. To render complex custom SwiftUI layouts (like lists with buttons, graphs, and stats) from the menu bar icon, you must change the style.
**Action:** Use the `.menuBarExtraStyle(.window)` modifier on the `MenuBarExtra` to present it as a popover window instead of a standard list menu.
## 2026-06-17 - Smart Sleep Eco Mode (Low Power Integration)
**Learning:** MacOS can notify applications when the system sleeps or wakes up (`NSWorkspace.screensDidSleepNotification` and `NSWorkspace.screensDidWakeNotification`), and can provide current battery state via `ProcessInfo.processInfo.isLowPowerModeEnabled`.
**Action:** When building background processes or managers on MacOS, pause heavy workloads when the system screen turns off and the system is on low power mode, to heavily improve battery life, similar to browser tab freezing.
