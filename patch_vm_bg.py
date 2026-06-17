import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

find_str_logs = """    public func streamLogs(for id: String) async {
        // Czyścimy poprzednie logi za każdym razem, gdy wywołujemy metodę dla nowego kontenera
        currentLogs.removeAll()

        let stream = daemon.streamLogs(for: id)

        // Czekamy w pętli na każdą nową wygenerowaną linię
        for await line in stream {
            // Ze względu na mechanizmy `.task` w SwiftUI, kiedy element straci na ważności
            // (użytkownik kliknie inny kontener), pętla automatycznie zostanie odwołana i zakończona.
            currentLogs.append(line)
        }
    }"""

replace_str_logs = """    public func streamLogs(for id: String) async {
        // Czyścimy poprzednie logi za każdym razem, gdy wywołujemy metodę dla nowego kontenera
        currentLogs.removeAll()

        let qos: DispatchQoS = .utility
        let isBg = (workload(for: id) as? VesselWorkload)?.container?.isBackground ?? false
        let label = "com.vessel.daemon.logs"

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue(label: label, qos: isBg ? .background : qos).async {
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

# Wait, `(workload(for: id) as? VesselWorkload)?.container` won't work because workload is an enum.
# Correct way:
# let isBg = { if case .container(let c) = workload(for: id) { return c.isBackground } else { return false } }()

replace_str_logs = """    public func streamLogs(for id: String) async {
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

cvm = cvm.replace(find_str_logs, replace_str_logs)

find_str_stats = """        if activeStatsTasks[id] == nil {
            activeStatsTasks[id] = Task { [weak self] in
                guard let self = self else { return }
                do {
                    let stream = try await daemon.startStatsStream(containerId: id)
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
            }
        }"""

replace_str_stats = """        if activeStatsTasks[id] == nil {
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

cvm = cvm.replace(find_str_stats, replace_str_stats)

with open(cvm_path, "w") as f:
    f.write(cvm)
