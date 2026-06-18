import Foundation
import Observation
import SwiftUI
import Containerization
import UserNotifications
import AppKit

func viewModelLog(_ msg: String) {
    let logFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/daemon.log")
    let text = "[\(Date())] \(msg)\n"
    if let data = text.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            // Security Enhancement: Use atomic writes and restrict permissions for log files
            try? data.write(to: logFile, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logFile.path)
        }
    }
}

public class PipeWriter: Containerization.Writer, @unchecked Sendable {
    let fileHandle: FileHandle
    public init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    public func write(_ data: Data) throws {
        if #available(macOS 10.15.4, *) {
            try fileHandle.write(contentsOf: data)
        } else {
            fileHandle.write(data)
        }
    }
    public func close() throws {
        try fileHandle.close()
    }
}

public class PipeReader: Containerization.ReaderStream, @unchecked Sendable {
    let dataStream: AsyncStream<Data>
    public init(fileHandle: FileHandle) {
        self.dataStream = AsyncStream<Data> { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { @Sendable _ in
                fileHandle.readabilityHandler = nil
            }
        }
    }
    public func stream() -> AsyncStream<Data> {
        return self.dataStream
    }
}

public struct LogLine: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let text: String
    public init(_ text: String) { self.text = text }
}

@Observable
public class ContainerViewModel: @unchecked Sendable {
    public var workloads: [VesselWorkload] = []
    public var domainRules: [DomainRule] = []
    
    // Zbiera ID kontenerów, na których aktualnie wykonywana jest asynchroniczna operacja, by blokować interfejs UI
    public var loadingContainers: Set<String> = []
    
    // Aktualnie strumieniowane logi wybranego kontenera
    public var currentLogs: [String] = []
    
    // Shell State
    public var shellInputPipes: [String: Pipe] = [:]
    public var shellOutputPipes: [String: Pipe] = [:]
    public var publishedStats: [String: StatsModel] = [:]
    public var statsHistory: [String: [StatsModel]] = [:]
    private var shellProcesses: [String: LinuxProcess] = [:]

    // ⚡ Bolt Optimization: Use reference counting to share a single background stats stream
    // across multiple views without dropping updates when one view disappears.
    private var activeStatsSubscriptionCounts: [String: Int] = [:]
    private var activeStatsTasks: [String: Task<Void, Never>] = [:]
    
    public var errorMessage: String? = nil
    
    private let daemon = ContainerDaemon()
    
    @MainActor
    public init() {
        Task {
            await fetchInitialWorkloads()
        }
    }
    
    @MainActor
    private func fetchInitialWorkloads() async {
        do {
            self.workloads = try await daemon.fetchActiveWorkloads()
            self.domainRules = daemon.fetchDomainRules()
        } catch {
            print("Błąd podczas pobierania workloadów: \(error.localizedDescription)")
            self.workloads = []
            self.domainRules = daemon.fetchDomainRules()
        }
    }
    
    @MainActor
    public func fetchContainers() async {
        do {
            self.workloads = try await daemon.fetchActiveWorkloads()
            self.domainRules = daemon.fetchDomainRules()
        } catch {
            print("Błąd: \(error.localizedDescription)")
        }
    }

    public func addDomainRule(source: VesselDomain, target: VesselDomain, isAllowed: Bool) {
        daemon.addDomainRule(DomainRule(source: source, target: target, isAllowed: isAllowed))
        Task { @MainActor in await self.fetchContainers() }
    }

    public func removeDomainRule(id: UUID) {
        daemon.removeDomainRule(id: id)
        Task { @MainActor in await self.fetchContainers() }
    }

    public func workload(for id: String) -> VesselWorkload? {
        return workloads.first { 
            switch $0 {
            case .container(let c): return c.id == id
            case .pod(let p): return p.id == id
            }
        }
    }
    @MainActor
    public func createContainer(name: String, image: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, isBackground: Bool, cpus: Int, memoryGB: Double, envVars: [String: String], volumes: [VesselVolume], portForwards: [VesselPortForward], domain: VesselDomain = .generic) async {
        await checkAndRequestNotificationAuthorization()


        let newId = UUID().uuidString
        loadingContainers.insert(newId)
        
        // Add a temporary container to the UI
        let placeholder = VesselContainer(id: newId, name: name, subtitle: "WORKLOAD", image: image, status: .creating, isBackground: isBackground, portForwards: portForwards, domain: domain)
        self.workloads.insert(.container(placeholder), at: 0)
        
        defer { loadingContainers.remove(newId) }
        
        do {
            try await daemon.start(containerId: newId, imageReference: image, name: name, rootfsSizeGB: rootfsSizeGB, rosetta: rosetta, networking: networking, isBackground: isBackground, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: volumes, portForwards: portForwards, domain: domain)
            await fetchInitialWorkloads()
            sendBuildCompletedNotification(containerName: name)
        } catch {
            print("Błąd podczas tworzenia kontenera: \(error.localizedDescription)")
            self.errorMessage = "Failed to create container: \(error.localizedDescription)"
            self.workloads.removeAll(where: { 
                if case .container(let c) = $0 { return c.id == newId }
                return false
            })
        }
    }

    @MainActor
    private func checkAndRequestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let alert = NSAlert()
            alert.messageText = "Wymagane uprawnienia"
            alert.informativeText = "Prosimy o zgodę na powiadomienia, aby powiadamiać o błędach budowania oraz awariach kontenerów."
            alert.addButton(withTitle: "OK")
            alert.runModal()

            do {
                try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("Failed to request notification authorization: \(error)")
            }
        }
    }

    private func sendBuildCompletedNotification(containerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Completed"
        content.body = "Zakończono tworzenie kontenera \(containerName)."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    public func notifyCrash(containerId: String, containerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Container Crash / OOM"
        content.body = "Krytyczny błąd: kontener \(containerName) uległ awarii."
        content.categoryIdentifier = "CRASH_CATEGORY"
        content.userInfo = ["containerId": containerId]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    @MainActor
    public func startContainer(id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) } 
        
        do {
            try await daemon.start(containerId: id)
            await fetchInitialWorkloads()
            
            Task { await streamLogs(for: id) }
            Task { await subscribeToStats(for: id) }
        } catch {
            print("Błąd podczas uruchamiania kontenera: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    public func startPod(url: URL) async {
        do {
            try await daemon.startPod(yamlPath: url)
            await fetchInitialWorkloads()
        } catch {
            print("Błąd podczas uruchamiania poda: \(error.localizedDescription)")
            self.errorMessage = "Failed to start pod: \(error.localizedDescription)"
        }
    }
    

    @MainActor
    public func pauseAllWorkloads() async {
        do {
            try await daemon.pauseAll()
            await fetchInitialWorkloads()
        } catch {
            print("Error pausing workloads: \(error)")
        }
    }

    @MainActor
    public func resumeAllWorkloads() async {
        do {
            try await daemon.resumeAll()
            await fetchInitialWorkloads()
        } catch {
            print("Error resuming workloads: \(error)")
        }
    }
    @MainActor
    public func stopContainer(id: String, force: Bool = false) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }
        
        do {
            try await daemon.stop(containerId: id, force: force)
            await fetchInitialWorkloads()
        } catch {
            print("Błąd podczas zatrzymywania kontenera: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    public func deleteContainer(id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }
        
        do {
            try await daemon.delete(containerId: id)
            await fetchInitialWorkloads()
        } catch {
            print("Błąd podczas usuwania kontenera: \(error.localizedDescription)")
            self.errorMessage = "Failed to delete container: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func streamLogs(for id: String) async {
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
                        let d = self.daemon
                        let stream = d.streamLogs(for: id)
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
    }
    
    @MainActor
    public func startShell(for id: String) async {
        if shellProcesses[id] != nil { return } // Already running
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        
        shellInputPipes[id] = inputPipe
        shellOutputPipes[id] = outputPipe
        
        let writer = PipeWriter(fileHandle: outputPipe.fileHandleForWriting)
        let reader = PipeReader(fileHandle: inputPipe.fileHandleForReading)
        
        viewModelLog("Starting shell for \(id)...")
        
        do {
            let process = try await daemon.execShell(containerId: id, stdin: reader, stdout: writer)
            shellProcesses[id] = process
            viewModelLog("Shell started successfully for \(id)")
        } catch {
            viewModelLog("Shell start error: \(error)")
            shellInputPipes.removeValue(forKey: id)
            shellOutputPipes.removeValue(forKey: id)
        }
    }
    
    @MainActor
    public func toggleShell(for id: String) async {
        if shellProcesses[id] != nil {
            shellProcesses.removeValue(forKey: id)
            shellInputPipes.removeValue(forKey: id)
            shellOutputPipes.removeValue(forKey: id)
        } else {
            await startShell(for: id)
        }
    }
    
    @MainActor
    public func subscribeToStats(for id: String) async {
        // ⚡ Bolt Optimization: Prevent redundant stats polling processes while supporting multiple subscribers.
        // Multiple views (like ContainersListView and ContainerDetailView) can request stats concurrently.
        // Reference count the subscriptions and share a single background task per container.
        let currentCount = activeStatsSubscriptionCounts[id] ?? 0
        activeStatsSubscriptionCounts[id] = currentCount + 1

        defer {
            let newCount = (activeStatsSubscriptionCounts[id] ?? 1) - 1
            if newCount <= 0 {
                activeStatsSubscriptionCounts.removeValue(forKey: id)
                activeStatsTasks[id]?.cancel()
                activeStatsTasks.removeValue(forKey: id)
            } else {
                activeStatsSubscriptionCounts[id] = newCount
            }
        }

        if activeStatsTasks[id] == nil {
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
                                    let d = self.daemon
                                    let stream = try await d.startStatsStream(containerId: id)
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
                                    viewModelLog("Failed to subscribe to stats for \(id): \(error)")
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
        }

        // Suspend the caller indefinitely so its `.task` remains active.
        // When the view disappears, this `Task.sleep` is cancelled, triggering the `defer` block.
        try? await Task.sleep(nanoseconds: UInt64.max)
    }

    @MainActor
    public func stopShell(for id: String) {
        // Zatrzymanie procesów i posprzątanie zasobów
        shellProcesses.removeValue(forKey: id)
        shellInputPipes.removeValue(forKey: id)
        shellOutputPipes.removeValue(forKey: id)
    }
}

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
