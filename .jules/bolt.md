## 2024-06-18 - SwiftUI View lifecycle with expensive subscriptions
**Learning:** In SwiftUI, `onAppear` or multiple views rendering the same model state can easily trigger background tasks redundantly. In `ContainerViewModel`, this caused multiple instances of `sh` executing inside the container VM just to fetch stats.
**Action:** When a method creates a long-running streaming subscription (especially background shells/processes), always use a tracking structure (like `Set`) in the ViewModel alongside `defer { tracking.remove(id) }` to prevent redundant overlapping streams on the same target.
## 2024-06-13 - [Memory Allocation Optimization]
**Learning:** Using `components(separatedBy:)` in hot paths (like a stats polling loop running every 1 second) causes excessive String and Array allocations because it produces arrays of fully initialized Strings, even for empty tokens.
**Action:** Use `.split(whereSeparator:)` instead of `.components(separatedBy:)` in high-frequency string parsing routines. It returns `Substring` (a zero-allocation view into the original string) and automatically ignores empty items without requiring `.filter { !$0.isEmpty }`.
