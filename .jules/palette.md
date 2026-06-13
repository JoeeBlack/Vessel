## 2024-05-14 - Initialize Palette Journal
**Learning:** Initializing palette journal for recording critical UX/a11y learnings.
**Action:** Always document significant UX and accessibility insights here.

## 2024-06-13 - SwiftUI Accessibility and Tooltips
**Learning:** In SwiftUI for macOS, adding the `.help("text")` modifier to interactive elements like `Button` natively handles both visual tooltips and screen reader accessibility labels, making it an excellent all-in-one UX improvement for icon-only buttons.
**Action:** Always use the `.help()` modifier for icon-only buttons or complex UI components in SwiftUI macOS projects instead of separate `accessibilityLabel` modifiers unless specific screen reader hints are required.

## 2024-05-14 - Missing Accessibility Labels on Icon-Only Buttons
**Learning:** Found multiple instances of icon-only buttons (`Image(systemName: ...)`) lacking `accessibilityLabel` and `help` modifiers across `ImagesListView.swift` and `CreateContainerView.swift`. This makes the UI completely inaccessible to VoiceOver users and unclear for sighted users unsure of the icon's meaning.
**Action:** Always add `.help("Description")` for tooltips and `.accessibilityLabel("Description")` to ALL icon-only buttons as a standard practice in this design system.
