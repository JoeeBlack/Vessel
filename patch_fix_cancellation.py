import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

# Fix streamLogs
find_str_logs = """        let qos: DispatchQoS = isBg ? .background : .utility

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue(label: "com.vessel.daemon.logs", qos: qos).async {
                Task {
                    let stream = self.daemon.streamLogs(for: id)
                    for await line in stream {
                        await MainActor.run {
                            self.currentLogs.append(line)
                        }
                    }
                    continuation.resume()
                }
            }
        }"""

replace_str_logs = """        let qos: DispatchQoS = isBg ? .background : .utility

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue(label: "com.vessel.daemon.logs", qos: qos).async {
                    let innerTask = Task {
                        let stream = self.daemon.streamLogs(for: id)
                        for await line in stream {
                            if Task.isCancelled { break }
                            await MainActor.run {
                                self.currentLogs.append(line)
                            }
                        }
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            // Need a way to cancel the inner task?
            // In streamLogs, since it's just a UI view observing, we can avoid withCheckedContinuation if we use unstructured concurrency correctly, but the prompt says: "obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background"
            // Let's store the task reference, but swift concurrency is cleaner.
        }"""

# Actually, the reviewer said:
# "If `DispatchQueue` must strictly be used to launch an async stream, it must be paired with `withTaskCancellationHandler` so that when the outer continuation/task is cancelled, the inner unstructured `Task` has its `.cancel()` method explicitly invoked. Alternatively, simply using `Task(priority: .background)` natively handles this without `DispatchQueue` acrobatics."
# However, the user specifically requested: "obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background."
# Let's write a custom wrapper to hold the inner task reference for cancellation.
