## 2024-06-18 - SwiftUI View lifecycle with expensive subscriptions
**Learning:** In SwiftUI, `onAppear` or multiple views rendering the same model state can easily trigger background tasks redundantly. In `ContainerViewModel`, this caused multiple instances of `sh` executing inside the container VM just to fetch stats.
**Action:** When a method creates a long-running streaming subscription (especially background shells/processes), always use a tracking structure (like `Set`) in the ViewModel alongside `defer { tracking.remove(id) }` to prevent redundant overlapping streams on the same target.

## 2026-06-13 - [Memory Allocation Optimization]
**Learning:** Using `components(separatedBy:)` with string separators in high-frequency loops (like reading from a live stats stream) allocates intermediate `Array<String>` and multiple `String` objects for each call. This can severely bottleneck performance in hot paths.
**Action:** Use `range(of:)` to locate the substring and use `Substring` slicing (`str[..<range.lowerBound]` and `str[range.upperBound...]`) to extract sections without allocating new memory. Crucially, rely on Swift's standard library support for `Substring` parsing (e.g. `Double(substring)`) to avoid manually casting substrings back into strings, which negates the optimization.

## 2024-06-15 - Shared AsyncStream in SwiftUI
**Learning:** When multiple views (e.g., list view and detail view) subscribe to a background polling stream using a naive Set to prevent duplicate processes, the second caller returns immediately and completes its `.task`. When the first view disappears, its task cancels the shared stream, leaving the second view stranded without updates.
**Action:** Use a reference counting system combined with a shared background `Task`. Suspend the caller's `.task` using `try? await Task.sleep(nanoseconds: UInt64.max)` to ensure the view's lifecycle correctly manages the shared stream's reference count.

## 2024-06-16 - macOS 15 Build Issue with AT_RESOLVE_BENEATH in Swift System 1.7.2
**Learning:** The Swift System library version 1.7.2 introduced a reference to `AT_RESOLVE_BENEATH`, which has availability constraints requiring macOS 26+ (or macOS 16, typically not macOS 15.0). As a result, compiling Vessel on macOS-latest (macOS 15) fails with 'cannot find AT_RESOLVE_BENEATH in scope'.
**Action:** Pin the `swift-system` dependency to exactly `1.7.1` in `Package.swift` to bypass the availability error.

## 2024-10-24 - Canvas Line Charts for Live Metrics
**Learning:** SwiftUI `Chart` elements (View Diffing) can drop frames when performing high-frequency updates (e.g. 100ms) for live monitoring, whereas `Canvas` API drawing directly via Metal avoids view diffing stutter entirely, exactly like Activity Monitor does on macOS.
**Action:** Replace `Chart` in live data displays (like Container detail performance curves) with a lightweight, manual `Canvas` equivalent to retain high refresh rates without impacting the main thread render cycle.

## 2026-06-17 - Scroll View Optimization
**Learning:** Use `LazyVStack` instead of eager `VStack` or `LazyVGrid` to prevent off-screen `@State` initializations and unnecessary view rendering. Apply `.drawingGroup()` modifier to complex child view rows (those with backgrounds, shadows, multiple gradients, or complex nested loops) within lazy layouts to spłaszczyć je w pojedynczą bitmapę wyrenderowaną przez Metal na GPU, co eliminuje stuttering podczas przewijania.
**Action:** Apply this pattern on complex lists in SwiftUI to maintain high frame rate while keeping interactive capabilities intact.

## 2024-06-18 - String Lowercasing Allocation Penalty
**Learning:** In Swift, using `.lowercased()` for string comparisons (e.g., inside `.sorted { w1, w2 in w1.name.lowercased() < w2.name.lowercased() }`) or searching (`text.lowercased().contains(...)`) allocates entirely new `String` objects in memory. This causes massive memory overhead and stuttering in UI performance, especially in list rendering paths or high-frequency processing loops (like terminal text streams).
**Action:** Use `.localizedCaseInsensitiveCompare` for sorting and `.localizedCaseInsensitiveContains` for substring matching. These methods perform in-place, allocation-free case-insensitive comparisons, significantly boosting performance.

## 2026-06-18 - Replacing declarative charts with Canvas
**Learning:** Declarative Charts (like Swift Charts) use complex view diffing logic that can cause CPU spikes and dropped frames when subjected to high-frequency state changes (e.g. 100ms real-time metric updates in monitoring dashboards).
**Action:** When creating high-frequency live updating graphs in SwiftUI, bypass `Chart` views and use immediate-mode rendering via the `Canvas` API to push drawing operations directly to Metal, thereby freeing the main thread.

## 2026-06-19 - Avoid Repeated UserDefaults Decoding
**Learning:** In Swift, repeatedly accessing and decoding complex collections (like dictionaries) directly from `UserDefaults` in high-frequency access paths incurs significant disk I/O and decoding overhead.
**Action:** Use a thread-safe in-memory cache synchronized with `UserDefaults` to resolve this.

## 2024-06-21 - Concurrent Container Teardown
Replaced sequential `await` execution with `withTaskGroup` in `ContainerDaemon.swift`'s `delete(containerId:)` method.
Previously, shutting down a pod with multiple containers halted sequentially, summing the teardown times (O(N)).
With `TaskGroup`, all containers receive the stop command in parallel, bringing the total time bound to the single longest container teardown latency (O(1)).

## 2024-06-21 - Concurrent Pod Stop
- Replaced sequential `await container.stop()` in `ContainerDaemon.swift` for pods with a concurrent `withTaskGroup`.
- This converts an O(N) sequential stop latency into an O(1) concurrent latency, significantly speeding up the shutdown of large pods.

## 2026-02-20 - Concurrent Operations
* In Swift codebases like Vessel, avoid executing asynchronous I/O operations (such as container start/stop/resume routines) sequentially inside a loop. Instead, wrap them in a `withTaskGroup` or `withThrowingTaskGroup` to process them concurrently, significantly reducing execution latency.

### 2025-06-28
* **What**: Replaced synchronous `Data(contentsOf:)` with a chunked async-aware file read using `FileHandle`.
* **Why**: The synchronous read in `FileReader.read()` blocked the Swift cooperative thread pool, potentially causing starvation when reading large files. Using a chunked approach with `await Task.yield()` fixes this.
* **Measured Improvement**: Replaced a blocking call that held a thread for the entire file read duration with a chunked `read` operation that yields between chunks, allowing other concurrent tasks to progress. The testing environment didn't have a Swift toolchain, preventing direct benchmark execution, but code inspection confirms the structural change.

## 2026-02-20
Offloaded synchronous I/O from the main UI thread during volume exploration to prevent interface stutter using `try await Task.detached { ... }.value`.
