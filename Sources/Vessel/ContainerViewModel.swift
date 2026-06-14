import Foundation
import Observation
import SwiftUI
import Containerization

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
public class ContainerViewModel {
    public var workloads: [VesselWorkload] = []
    
    // Zbiera ID kontenerów, na których aktualnie wykonywana jest asynchroniczna operacja, by blokować interfejs UI
    public var loadingContainers: Set<String> = []
    
    // Aktualnie strumieniowane logi wybranego kontenera
    public var currentLogs: [String] = []
    
    // Shell State
    public var shellInputPipes: [String: Pipe] = [:]
    public var shellOutputPipes: [String: Pipe] = [:]
    public var publishedStats: [String: StatsModel] = [:]
    private var shellProcesses: [String: LinuxProcess] = [:]

    // ⚡ Bolt Optimization: Use reference counting to share a single background stats stream
    // across multiple views without dropping updates when one view disappears.
    private var activeStatsSubscriptionCounts: [String: Int] = [:]
    private var activeStatsTasks: [String: Task<Void, Never>] = [:]
    
    public var errorMessage: String? = nil
    
    private let daemon = ContainerDaemon()
    
    public init() {
        Task {
            await fetchInitialWorkloads()
        }
    }
    
    @MainActor
    private func fetchInitialWorkloads() async {
        do {
            self.workloads = try await daemon.fetchActiveWorkloads()
        } catch {
            print("Błąd podczas pobierania workloadów: \(error.localizedDescription)")
            self.workloads = []
        }
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
    public func createContainer(name: String, image: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, cpus: Int, memoryGB: Double, envVars: [String: String], volumes: [VesselVolume]) async {
        let newId = UUID().uuidString
        loadingContainers.insert(newId)
        
        // Add a temporary container to the UI
        let placeholder = VesselContainer(id: newId, name: name, subtitle: "WORKLOAD", image: image, status: .creating)
        self.workloads.insert(.container(placeholder), at: 0)
        
        defer { loadingContainers.remove(newId) }
        
        do {
            try await daemon.start(containerId: newId, imageReference: image, name: name, rootfsSizeGB: rootfsSizeGB, rosetta: rosetta, networking: networking, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: volumes)
            await fetchInitialWorkloads()
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
    public func stopContainer(id: String) async {
        loadingContainers.insert(id)
        defer { loadingContainers.remove(id) }
        
        do {
            try await daemon.stop(containerId: id)
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
        
        let stream = daemon.streamLogs(for: id)
        
        // Czekamy w pętli na każdą nową wygenerowaną linię
        for await line in stream {
            // Ze względu na mechanizmy `.task` w SwiftUI, kiedy element straci na ważności 
            // (użytkownik kliknie inny kontener), pętla automatycznie zostanie odwołana i zakończona.
            currentLogs.append(line)
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
            activeStatsTasks[id] = Task { [weak self] in
                guard let self = self else { return }
                do {
                    let stream = try await daemon.startStatsStream(containerId: id)
                    for await model in stream {
                        await MainActor.run { self.publishedStats[id] = model }
                    }
                } catch {
                    viewModelLog("Failed to subscribe to stats for \(id): \(error)")
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
