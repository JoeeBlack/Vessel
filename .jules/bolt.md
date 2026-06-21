# 2024-05-14

- Replaced sequential `await container.stop()` in `ContainerDaemon.swift` for pods with a concurrent `withTaskGroup`.
- This converts an O(N) sequential stop latency into an O(1) concurrent latency, significantly speeding up the shutdown of large pods.
