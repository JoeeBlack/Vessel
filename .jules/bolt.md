## 2026-02-20
Offloaded synchronous I/O from the main UI thread during volume exploration to prevent interface stutter using `try await Task.detached { ... }.value`.
