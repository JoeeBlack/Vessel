import Foundation
import Observation
import SwiftUI
import Containerization
import UserNotifications
import AppKit
import OSLog
import Yams

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
        try fileHandle.write(contentsOf: data)
    }
}

public class NullWriter: Containerization.Writer, @unchecked Sendable {
    public init() {}
    public func write(_ data: Data) throws {}
}

@Observable
public class ContainerViewModel {
    public var workloads: [VesselWorkload] = []
    public var images: [VesselImage] = []
    public var networks: [VesselNetwork] = []
    public var volumes: [VesselVolumeDefinition] = []
    
    public var isRefreshing = false
    public var errorMessage: String? = nil
    
    private let daemon = ContainerDaemon()
    private let logger = Logger(subsystem: "com.vessel.app", category: "ViewModel")
    
    public init() {
        Task {
            await fetchInitialWorkloads()
        }
    }
    
    @MainActor
    public func fetchInitialWorkloads() async {
        isRefreshing = true
        do {
            self.workloads = try await daemon.fetchActiveWorkloads()
            self.images = try await daemon.fetchImages()
            self.networks = try await daemon.fetchNetworks()
            self.volumes = try await daemon.fetchVolumes()
        } catch {
            logger.error("Error fetching workloads: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to load initial data"
        }
        isRefreshing = false
    }
    
    @MainActor
    public func pollWorkloads() async {
        do {
            self.workloads = try await daemon.fetchActiveWorkloads()
        } catch {
            logger.error("Error polling workloads: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func workload(for id: String) -> VesselWorkload? {
        return workloads.first { $0.id == id }
    }

    @MainActor
    public func startContainer(id: String, image: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, isBackground: Bool, cpus: Int, memoryGB: Double, envVars: [String: String], volumes: [VesselVolume], portForwards: [VesselPortForward], domain: VesselDomain) async {
        do {
            // Check if it's already created/stopped or we are creating a new one
            if workloads.contains(where: { $0.id == id }) {
                try await daemon.start(containerId: id)
            } else {
                let newId = UUID().uuidString
                try await daemon.start(containerId: newId, imageReference: image, name: name, rootfsSizeGB: rootfsSizeGB, rosetta: rosetta, networking: networking, isBackground: isBackground, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: volumes, portForwards: portForwards, domain: domain)
            }
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error starting container: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to start container: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func stopContainer(id: String) async {
        do {
            try await daemon.stop(containerId: id)
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error stopping container: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to stop container: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func restartContainer(id: String) async {
        do {
            try await daemon.stop(containerId: id)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await daemon.start(containerId: id)
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error restarting container: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to restart container: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func deleteContainer(id: String) async {
        do {
            try await daemon.delete(containerId: id)
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error deleting container: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to delete container: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func startContainerQuick(id: String) async {
        do {
            try await daemon.start(containerId: id)
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error starting container: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    @MainActor
    public func startPod(url: URL) async {
        do {
            // Read yaml and parse it
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            let projectName = url.deletingPathExtension().lastPathComponent
            let project = try ComposeParser.parse(yaml: yamlString, projectName: projectName)

            // Inject secrets and env vars BEFORE sending to daemon
            let envFileUrl = url.deletingLastPathComponent().appendingPathComponent(".env")
            let injectedProject = ComposeParser.injectSecrets(into: project, envFileUrl: envFileUrl)

            let yamlEncoder = YAMLEncoder()
            var servicesDef: [String: ComposeServiceDef] = [:]
            for service in injectedProject.services {
                let envDef: EnvironmentDef = .dictionary(service.environment.mapValues { AnyString(value: $0) })
                let serviceDef = ComposeServiceDef(image: service.image, environment: envDef, ports: service.ports.map { .string($0) }, volumes: service.volumes.map { .string($0) })
                servicesDef[service.name] = serviceDef
            }
            let fileDef = ComposeFileDef(services: servicesDef)
            let tempYamlString = try yamlEncoder.encode(fileDef)

            let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("yml")
            try tempYamlString.write(to: tempUrl, atomically: true, encoding: .utf8)

            try await daemon.startPod(yamlPath: tempUrl)
            await fetchInitialWorkloads()

            try? FileManager.default.removeItem(at: tempUrl)
        } catch {
            logger.error("Error starting pod: \(error.localizedDescription, privacy: .public)")
            self.errorMessage = "Failed to start pod: \(error.localizedDescription)"
        }
    }
    

    @MainActor
    public func pauseAllWorkloads() async {
        do {
            try await daemon.pauseAll()
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error pausing workloads: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    public func resumeAllWorkloads() async {
        do {
            try await daemon.resumeAll()
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error resuming workloads: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func streamLogs(for id: String) -> AsyncStream<String> {
        return daemon.streamLogs(for: id)
    }

    @MainActor
    public func deleteImage(id: String) async {
        do {
            try await daemon.deleteImage(reference: id)
            await fetchInitialWorkloads()
        } catch {
            logger.error("Error deleting image: \(error.localizedDescription, privacy: .public)")
        }
    }
}
