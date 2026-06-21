# 2024-06-21

## Concurrent Container Teardown
Replaced sequential `await` execution with `withTaskGroup` in `ContainerDaemon.swift`'s `delete(containerId:)` method.
Previously, shutting down a pod with multiple containers halted sequentially, summing the teardown times (O(N)).
With `TaskGroup`, all containers receive the stop command in parallel, bringing the total time bound to the single longest container teardown latency (O(1)).

## Concurrent Pod Stop
- Replaced sequential `await container.stop()` in `ContainerDaemon.swift` for pods with a concurrent `withTaskGroup`.
- This converts an O(N) sequential stop latency into an O(1) concurrent latency, significantly speeding up the shutdown of large pods.
