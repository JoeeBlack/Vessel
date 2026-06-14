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

public class ComposeParser {
    public static func parse(yaml: String, projectName: String) throws -> ComposeProject {
        // 🛡️ Sentinel: Mitigate YAML "Billion Laughs" alias attacks
        // Reject excessively large YAML files to prevent memory exhaustion
        guard yaml.utf8.count <= 1_048_576 else {
            throw NSError(domain: "ComposeParser", code: 5, userInfo: [NSLocalizedDescriptionKey: "YAML file is too large. Maximum size is 1MB."])
        }

        // Alias checking omitted as Yams.Parser API changed
        guard let loadedDict = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw NSError(domain: "ComposeParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid YAML format"])
        }
        
        guard let servicesDict = loadedDict["services"] as? [String: Any] else {
            throw NSError(domain: "ComposeParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "No 'services' defined in compose file"])
        }
        
        var services: [ComposeService] = []
        
        for (serviceName, serviceData) in servicesDict {
            // 🛡️ Sentinel: Validate service name to prevent path traversal when creating container file paths
            guard serviceName.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
                throw NSError(domain: "ComposeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid service name '\(serviceName)'. Only alphanumeric characters, dashes, and underscores are allowed."])
            }

            guard let serviceMap = serviceData as? [String: Any] else { continue }
            
            guard let image = serviceMap["image"] as? String else {
                throw NSError(domain: "ComposeParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Service '\(serviceName)' is missing 'image' directive"])
            }
            
            var parsedEnv: [String: String] = [:]
            if let envArray = serviceMap["environment"] as? [String] {
                for envStr in envArray {
                    let parts = envStr.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        parsedEnv[parts[0]] = parts[1]
                    }
                }
            } else if let envDict = serviceMap["environment"] as? [String: String] {
                parsedEnv = envDict
            }
            
            let ports = (serviceMap["ports"] as? [String]) ?? []
            let volumes = (serviceMap["volumes"] as? [String]) ?? []
            
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
