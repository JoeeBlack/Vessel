import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()


# streamLogs replacement
find_logs = """    public func streamLogs(for id: String) async {
        // Czyścimy poprzednie logi za każdym razem, gdy wywołujemy metodę dla nowego kontenera
        currentLogs.removeAll()

        let isBg: Bool = {
            if let w = workload(for: id), case .container(let c) = w {
                return c.isBackground
            }
            return false
        }()

        let qos: DispatchQoS = isBg ? .background : .utility

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
        }
    }"""

replace_logs = """    public func streamLogs(for id: String) async {
        // Czyścimy poprzednie logi za każdym razem, gdy wywołujemy metodę dla nowego kontenera
        currentLogs.removeAll()

        let isBg: Bool = {
            if let w = workload(for: id), case .container(let c) = w {
                return c.isBackground
            }
            return false
        }()

        let qos: DispatchQoS = isBg ? .background : .utility

        let taskWrapper = TaskWrapper()

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
                    taskWrapper.set(innerTask)
                }
            }
        } onCancel: {
            taskWrapper.cancel()
        }
    }"""

cvm = cvm.replace(find_logs, replace_logs)

find_stats = """        if activeStatsTasks[id] == nil {
            let isBg: Bool = {
                if let w = workload(for: id), case .container(let c) = w {
                    return c.isBackground
                }
                return false
            }()
            let qos: DispatchQoS = isBg ? .background : .utility

            activeStatsTasks[id] = Task { [weak self] in
                guard let self = self else { return }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue(label: "com.vessel.daemon.stats", qos: qos).async {
                        Task {
                            do {
                                let stream = try await self.daemon.startStatsStream(containerId: id)
                                for await model in stream {
                                    await MainActor.run {
                                        self.publishedStats[id] = model
                                        var history = self.statsHistory[id] ?? []
                                        history.append(model)
                                        if history.count > 60 { // keep last 60 seconds
                                            history.removeFirst(history.count - 60)
                                        }
                                        self.statsHistory[id] = history
                                    }
                                }
                            } catch {
                                viewModelLog("Failed to subscribe to stats for \\(id): \\(error)")
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }"""

replace_stats = """        if activeStatsTasks[id] == nil {
            let isBg: Bool = {
                if let w = workload(for: id), case .container(let c) = w {
                    return c.isBackground
                }
                return false
            }()
            let qos: DispatchQoS = isBg ? .background : .utility

            activeStatsTasks[id] = Task { [weak self] in
                guard let self = self else { return }
                let taskWrapper = TaskWrapper()

                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        DispatchQueue(label: "com.vessel.daemon.stats", qos: qos).async {
                            let innerTask = Task {
                                do {
                                    let stream = try await self.daemon.startStatsStream(containerId: id)
                                    for await model in stream {
                                        if Task.isCancelled { break }
                                        await MainActor.run {
                                            self.publishedStats[id] = model
                                            var history = self.statsHistory[id] ?? []
                                            history.append(model)
                                            if history.count > 60 { // keep last 60 seconds
                                                history.removeFirst(history.count - 60)
                                            }
                                            self.statsHistory[id] = history
                                        }
                                    }
                                } catch {
                                    viewModelLog("Failed to subscribe to stats for \\(id): \\(error)")
                                }
                                continuation.resume()
                            }
                            taskWrapper.set(innerTask)
                        }
                    }
                } onCancel: {
                    taskWrapper.cancel()
                }
            }
        }"""

cvm = cvm.replace(find_stats, replace_stats)

# Add TaskWrapper helper
task_wrapper = """
class TaskWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            task.cancel()
        } else {
            self.task = task
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        task?.cancel()
    }
}
"""

if "class TaskWrapper" not in cvm:
    cvm += task_wrapper

with open(cvm_path, "w") as f:
    f.write(cvm)
