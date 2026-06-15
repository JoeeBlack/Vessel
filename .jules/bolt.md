## 2024-06-13 - Replace .onAppear { Task {} } with .task
**Learning:** In SwiftUI, launching asynchronous tasks using `.onAppear { Task { ... } }` is a common performance anti-pattern. If the view disappears, the task continues running in the background unless explicitly tracked and cancelled, leading to memory leaks and wasted CPU cycles (e.g. infinite polling loops for container stats).
**Action:** Use `.task { ... }` or `.task(id:) { ... }` instead. SwiftUI automatically cancels tasks created with `.task` when the view disappears or the `id` changes, ensuring clean, automatic resource management without manual `Task` tracking.

## 2024-06-13 - Replace .onAppear { Task {} } with .task
**Learning:** In SwiftUI, launching asynchronous tasks using `.onAppear { Task { ... } }` is a common performance anti-pattern. If the view disappears, the task continues running in the background unless explicitly tracked and cancelled, leading to memory leaks and wasted CPU cycles (e.g. infinite polling loops for container stats).
**Action:** Use `.task { ... }` or `.task(id:) { ... }` instead. SwiftUI automatically cancels tasks created with `.task` when the view disappears or the `id` changes, ensuring clean, automatic resource management without manual `Task` tracking.

## 2024-06-14 - Replace .filter { ... }.count with .count(where: ...)
**Learning:** In Swift, calling `.filter { ... }.count` evaluates the closure for all elements and allocates an entirely new array just to calculate its size. This wastes memory and CPU cycles, especially for large collections or code evaluated frequently (like computed properties in SwiftUI views). Swift provides `.count(where:)` which counts matching elements in a single pass without allocating any intermediate collections.
**Action:** Always prefer `.count(where:)` over `.filter { ... }.count` to efficiently count elements that match a predicate in O(N) time with O(1) space.

## 2024-06-15 - Shared AsyncStream in SwiftUI
**Learning:** When multiple views (e.g., list view and detail view) subscribe to a background polling stream using a naive Set to prevent duplicate processes, the second caller returns immediately and completes its `.task`. When the first view disappears, its task cancels the shared stream, leaving the second view stranded without updates.
**Action:** Use a reference counting system combined with a shared background `Task`. Suspend the caller's `.task` using `try? await Task.sleep(nanoseconds: UInt64.max)` to ensure the view's lifecycle correctly manages the shared stream's reference count.

## 2024-06-16 - macOS 15 Build Issue with AT_RESOLVE_BENEATH in Swift System 1.7.2
**Learning:** The Swift System library version 1.7.2 introduced a reference to `AT_RESOLVE_BENEATH`, which has availability constraints requiring macOS 26+ (or macOS 16, typically not macOS 15.0). As a result, compiling Vessel on macOS-latest (macOS 15) fails with 'cannot find AT_RESOLVE_BENEATH in scope'.
**Action:** Pin the `swift-system` dependency to exactly `1.7.1` in `Package.swift` to bypass the availability error.
