import Foundation

// MARK: - Enums
public enum VesselStatus: String, CaseIterable, Codable, Sendable {
    case running = "running"
    case paused = "paused"
    case stopped = "stopped"
    case error = "error"
    case creating = "creating"
    case starting = "starting"
    case unknown = "unknown"
}

public enum VesselDomain: String, CaseIterable, Codable, Hashable {
    case generic = "generic"
    case personal = "personal"
    case work = "work"
    case development = "dev"
    case untrusted = "untrusted"
}

public struct DomainRule: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let source: VesselDomain
    public let target: VesselDomain
    public let isAllowed: Bool

    public init(id: UUID = UUID(), source: VesselDomain, target: VesselDomain, isAllowed: Bool) {
        self.id = id
        self.source = source
        self.target = target
        self.isAllowed = isAllowed
    }
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

public struct VesselPortForward: Codable, Hashable, Sendable {
    public let hostPort: Int
    public let containerPort: Int

    public init(hostPort: Int, containerPort: Int) {
        self.hostPort = hostPort
        self.containerPort = containerPort
    }
}

public struct VesselPod: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let status: VesselStatus
    public let containers: [VesselContainer]
    
    public let cpus: Int
    public let memoryGB: Double
    public let domain: VesselDomain
    
    public init(id: String, name: String, status: VesselStatus, containers: [VesselContainer], cpus: Int = 2, memoryGB: Double = 2.0, domain: VesselDomain = .generic) {
        self.id = id
        self.name = name
        self.status = status
        self.containers = containers
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.domain = domain
    }







    enum CodingKeys: String, CodingKey {
        case id, name, status, containers, cpus, memoryGB, domain
    }




    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encode(containers, forKey: .containers)
        try container.encode(cpus, forKey: .cpus)
        try container.encode(memoryGB, forKey: .memoryGB)
        try container.encode(domain, forKey: .domain)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.status = try container.decode(VesselStatus.self, forKey: .status)
        self.containers = try container.decode([VesselContainer].self, forKey: .containers)
        self.cpus = try container.decode(Int.self, forKey: .cpus)
        self.memoryGB = try container.decode(Double.self, forKey: .memoryGB)
        self.domain = try container.decodeIfPresent(VesselDomain.self, forKey: .domain) ?? .generic
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
    public let portForwards: [VesselPortForward]
    public let domain: VesselDomain
    
    public init(id: String, name: String, subtitle: String, image: String, status: VesselStatus, ipAddress: String? = nil, dnsName: String? = nil, uptime: String? = nil, ports: String? = nil, memoryUsage: String? = nil, volume: String? = nil, exitStatus: String? = nil, rosettaEnabled: Bool = false, networkingEnabled: Bool = true, rootfsSize: String = "8GB", cpus: Int = 2, memoryGB: Double = 2.0, envVars: [String: String] = [:], volumes: [VesselVolume] = [], portForwards: [VesselPortForward] = [], domain: VesselDomain = .generic) {
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
        self.portForwards = portForwards
        self.domain = domain
    }




    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, image, status, ipAddress, dnsName, uptime, ports, memoryUsage, volume, exitStatus, rosettaEnabled, networkingEnabled, rootfsSize, cpus, memoryGB, envVars, volumes, portForwards, domain
    }




    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(image, forKey: .image)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(ipAddress, forKey: .ipAddress)
        try container.encodeIfPresent(dnsName, forKey: .dnsName)
        try container.encodeIfPresent(uptime, forKey: .uptime)
        try container.encodeIfPresent(ports, forKey: .ports)
        try container.encodeIfPresent(memoryUsage, forKey: .memoryUsage)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(exitStatus, forKey: .exitStatus)
        try container.encode(rosettaEnabled, forKey: .rosettaEnabled)
        try container.encode(networkingEnabled, forKey: .networkingEnabled)
        try container.encode(rootfsSize, forKey: .rootfsSize)
        try container.encode(cpus, forKey: .cpus)
        try container.encode(memoryGB, forKey: .memoryGB)
        try container.encode(envVars, forKey: .envVars)
        try container.encode(volumes, forKey: .volumes)
        try container.encode(portForwards, forKey: .portForwards)
        try container.encode(domain, forKey: .domain)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.image = try container.decode(String.self, forKey: .image)
        self.status = try container.decode(VesselStatus.self, forKey: .status)
        self.ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
        self.dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
        self.uptime = try container.decodeIfPresent(String.self, forKey: .uptime)
        self.ports = try container.decodeIfPresent(String.self, forKey: .ports)
        self.memoryUsage = try container.decodeIfPresent(String.self, forKey: .memoryUsage)
        self.volume = try container.decodeIfPresent(String.self, forKey: .volume)
        self.exitStatus = try container.decodeIfPresent(String.self, forKey: .exitStatus)
        self.rosettaEnabled = try container.decode(Bool.self, forKey: .rosettaEnabled)
        self.networkingEnabled = try container.decode(Bool.self, forKey: .networkingEnabled)
        self.rootfsSize = try container.decode(String.self, forKey: .rootfsSize)
        self.cpus = try container.decode(Int.self, forKey: .cpus)
        self.memoryGB = try container.decode(Double.self, forKey: .memoryGB)
        self.envVars = try container.decode([String: String].self, forKey: .envVars)
        self.volumes = try container.decode([VesselVolume].self, forKey: .volumes)
        self.portForwards = try container.decodeIfPresent([VesselPortForward].self, forKey: .portForwards) ?? []
        self.domain = try container.decodeIfPresent(VesselDomain.self, forKey: .domain) ?? .generic
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

