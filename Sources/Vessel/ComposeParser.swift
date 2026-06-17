import Foundation
import Yams

public struct ComposeService {
    public let name: String
    public let image: String
    public let environment: [String: String]
    public let ports: [String]
    public let volumes: [String]
}

public struct ComposeProject {
    public let name: String
    public let services: [ComposeService]
}

// MARK: - Codable Definitions for Compose Specification

struct ComposeFileDef: Codable {
    let services: [String: ComposeServiceDef]?
}

struct ComposeServiceDef: Codable {
    let image: String?
    let environment: EnvironmentDef?
    let ports: [PortDef]?
    let volumes: [VolumeDef]?
}

enum EnvironmentDef: Codable {
    case dictionary([String: AnyString])
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyString].self) {
            self = .dictionary(dict)
        } else if let list = try? container.decode([String].self) {
            self = .list(list)
        } else {
            self = .dictionary([:]) // Fallback
        }
    }
}

enum PortDef: Codable {
    case integer(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .integer(intVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.typeMismatch(PortDef.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String"))
        }
    }

    var stringValue: String {
        switch self {
        case .integer(let v): return String(v)
        case .string(let v): return v
        }
    }
}

enum VolumeDef: Codable {
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.typeMismatch(VolumeDef.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String for simple volume format"))
        }
    }

    var stringValue: String {
        switch self {
        case .string(let v): return v
        }
    }
}

struct AnyString: Codable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = String(intVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal ? "true" : "false"
        } else if let doubleVal = try? container.decode(Double.self) {
            value = String(doubleVal)
        } else {
            value = try container.decode(String.self)
        }
    }
}

public class ComposeParser {
    public static func parse(yaml: String, projectName: String) throws -> ComposeProject {
        // 🛡️ Sentinel: Mitigate YAML "Billion Laughs" alias attacks
        // Reject excessively large YAML files to prevent memory exhaustion
        guard yaml.utf8.count <= 1_048_576 else {
            throw NSError(domain: "ComposeParser", code: 5, userInfo: [NSLocalizedDescriptionKey: "YAML file is too large. Maximum size is 1MB."])
        }

        // 🛡️ Sentinel: Enforce alias limit to prevent memory exhaustion
        let parser = try Yams.Parser(yaml: yaml)
        var aliasCount = 0
        for event in parser {
            if case .alias = event {
                aliasCount += 1
                if aliasCount > 50 {
                    throw NSError(domain: "ComposeParser", code: 6, userInfo: [NSLocalizedDescriptionKey: "Too many YAML aliases. Possible Billion Laughs attack."])
                }
            }
        }

        let decoder = YAMLDecoder()
        guard let composeFile = try? decoder.decode(ComposeFileDef.self, from: yaml) else {
            throw NSError(domain: "ComposeParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid YAML format"])
        }
        
        guard let servicesDict = composeFile.services, !servicesDict.isEmpty else {
            throw NSError(domain: "ComposeParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "No 'services' defined in compose file"])
        }
        
        var services: [ComposeService] = []
        
        for (serviceName, serviceDef) in servicesDict {
            // 🛡️ Sentinel: Validate service name to prevent path traversal when creating container file paths
            guard serviceName.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
                throw NSError(domain: "ComposeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid service name '\(serviceName)'. Only alphanumeric characters, dashes, and underscores are allowed."])
            }

            guard let image = serviceDef.image else {
                throw NSError(domain: "ComposeParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Service '\(serviceName)' is missing 'image' directive"])
            }
            
            var parsedEnv: [String: String] = [:]
            if let env = serviceDef.environment {
                switch env {
                case .dictionary(let dict):
                    for (k, v) in dict {
                        parsedEnv[k] = v.value
                    }
                case .list(let list):
                    for envStr in list {
                        let parts = envStr.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            parsedEnv[parts[0]] = parts[1]
                        }
                    }
                }
            }
            
            let ports = serviceDef.ports?.map { $0.stringValue } ?? []
            let volumes = serviceDef.volumes?.map { $0.stringValue } ?? []
            
            let service = ComposeService(
                name: serviceName,
                image: image,
                environment: parsedEnv,
                ports: ports,
                volumes: volumes
            )
            services.append(service)
        }
        
        // Sort to maintain predictable order
        services.sort { $0.name < $1.name }
        
        return ComposeProject(name: projectName, services: services)
    }
}
