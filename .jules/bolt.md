## 2026-02-20
Offloaded synchronous I/O from the main UI thread during volume exploration to prevent interface stutter using `try await Task.detached { ... }.value`.
## 2026-06-29
Optimized vulnerability filtering and severity formatting by avoiding unnecessary intermediate array allocations using `.reduce(into:)` instead of `.filter { ... }.count`, and eliminated O(N log N) `String` allocations by replacing `.uppercased()` with `.localizedCaseInsensitiveCompare()` in sorting closures and switch statements.
