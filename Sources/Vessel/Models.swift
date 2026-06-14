import Foundation

// MARK: - Enums
public enum VesselStatus: String, CaseIterable, Codable, Sendable {
    case running = "running"
    case stopped = "stopped"
    case error = "error"
    case creating = "creating"
    case starting = "starting"
    case unknown = "unknown"
}

// MARK: - Models
public struct VesselVolume: Codable, Hashable, Sendable {
    public let host: String
    public let container: String
    
    public init(host: String, container: String) {
        self.host = host
        self.container = container
    }
}

public struct VesselPod: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let status: VesselStatus
    public let containers: [VesselContainer]
    
    public let cpus: Int
    public let memoryGB: Double
    
    public init(id: String, name: String, status: VesselStatus, containers: [VesselContainer], cpus: Int = 2, memoryGB: Double = 2.0) {
        self.id = id
        self.name = name
        self.status = status
        self.containers = containers
        self.cpus = cpus
        self.memoryGB = memoryGB
    }
}

public enum VesselWorkload: Identifiable, Hashable, Sendable {
    case container(VesselContainer)
    case pod(VesselPod)
    
    public var id: String {
        switch self {
        case .container(let c): return c.id
        case .pod(let p): return p.id
        }
    }
    
    public var name: String {
        switch self {
        case .container(let c): return c.name
        case .pod(let p): return p.name
        }
    }
}

public struct VesselContainer: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let image: String
    public let status: VesselStatus
    public let ipAddress: String?
    public let dnsName: String?
    public let uptime: String?
    public let ports: String?
    public let memoryUsage: String?
    public let volume: String?
    public let exitStatus: String?
    public let rosettaEnabled: Bool
    public let networkingEnabled: Bool
    public let rootfsSize: String
    
    // Persistence fields for recreation
    public let cpus: Int
    public let memoryGB: Double
    public let envVars: [String: String]
    public let volumes: [VesselVolume]
    
    public init(id: String, name: String, subtitle: String, image: String, status: VesselStatus, ipAddress: String? = nil, dnsName: String? = nil, uptime: String? = nil, ports: String? = nil, memoryUsage: String? = nil, volume: String? = nil, exitStatus: String? = nil, rosettaEnabled: Bool = false, networkingEnabled: Bool = true, rootfsSize: String = "8GB", cpus: Int = 2, memoryGB: Double = 2.0, envVars: [String: String] = [:], volumes: [VesselVolume] = []) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.image = image
        self.status = status
        self.ipAddress = ipAddress
        self.dnsName = dnsName
        self.uptime = uptime
        self.ports = ports
        self.memoryUsage = memoryUsage
        self.volume = volume
        self.exitStatus = exitStatus
        self.rosettaEnabled = rosettaEnabled
        self.networkingEnabled = networkingEnabled
        self.rootfsSize = rootfsSize
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.envVars = envVars
        self.volumes = volumes
    }
}

public struct VesselImage: Identifiable, Codable, Hashable {
    public let id: String
    public let repository: String
    public let tag: String
    public let size: String
    
    public init(id: String, repository: String, tag: String, size: String) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.size = size
    }
}

