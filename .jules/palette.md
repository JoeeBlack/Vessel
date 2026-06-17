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
## $(date +%Y-%m-%d) - Add Sensory Feedback (Haptics)
**Learning:** For a faster perceived app response time on macOS trackpads without CPU overhead, use `.sensoryFeedback(trigger:)` from macOS 14+. It can be toggled by coupling the condition inside the modifier logic with an `@AppStorage` variable.
**Action:** When adding micro-interactions to start/stop or errors in Apple platform apps, implement `.sensoryFeedback(.impact)` or `.sensoryFeedback(.error)` and ensure they are user-configurable.
