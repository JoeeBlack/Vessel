import Foundation

let arguments = CommandLine.arguments

// Default values for backward compatibility if launched without arguments
var command = "add-resolver"
var domain = "test"

if arguments.count >= 3 {
    command = arguments[1]
    domain = arguments[2]
}

if command == "add-resolver" {
    // Security Fix: Validate domain to prevent Path Traversal
    guard !domain.contains("/") && !domain.contains("..") else {
        print("Invalid domain name: contains invalid characters.")
        exit(1)
    }

    let contents = """
    domain \(domain)
    nameserver 127.0.0.1
    port 5353
    """

    let resolverDir = URL(fileURLWithPath: "/etc/resolver")
    let vesselResolverFile = resolverDir.appendingPathComponent(domain)

    do {
        if !FileManager.default.fileExists(atPath: resolverDir.path) {
            try FileManager.default.createDirectory(at: resolverDir, withIntermediateDirectories: true)
        }

        try contents.write(to: vesselResolverFile, atomically: true, encoding: .utf8)
        print("Successfully configured /etc/resolver/\(domain) for Magic DNS.")
    } catch {
        print("Failed to configure /etc/resolver/\(domain): \(error)")
        exit(1)
    }
}
exit(0)
