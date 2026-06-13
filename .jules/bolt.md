## 2024-06-13 - Replace .onAppear { Task {} } with .task
**Learning:** In SwiftUI, launching asynchronous tasks using `.onAppear { Task { ... } }` is a common performance anti-pattern. If the view disappears, the task continues running in the background unless explicitly tracked and cancelled, leading to memory leaks and wasted CPU cycles (e.g. infinite polling loops for container stats).
**Action:** Use `.task { ... }` or `.task(id:) { ... }` instead. SwiftUI automatically cancels tasks created with `.task` when the view disappears or the `id` changes, ensuring clean, automatic resource management without manual `Task` tracking.

## 2024-06-13 - Replace .onAppear { Task {} } with .task
**Learning:** In SwiftUI, launching asynchronous tasks using `.onAppear { Task { ... } }` is a common performance anti-pattern. If the view disappears, the task continues running in the background unless explicitly tracked and cancelled, leading to memory leaks and wasted CPU cycles (e.g. infinite polling loops for container stats).
**Action:** Use `.task { ... }` or `.task(id:) { ... }` instead. SwiftUI automatically cancels tasks created with `.task` when the view disappears or the `id` changes, ensuring clean, automatic resource management without manual `Task` tracking.
