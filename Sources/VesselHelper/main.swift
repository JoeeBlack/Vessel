import Foundation

let resolverDir = URL(fileURLWithPath: "/etc/resolver")
let vesselResolverFile = resolverDir.appendingPathComponent("test")

do {
    if !FileManager.default.fileExists(atPath: resolverDir.path) {
        try FileManager.default.createDirectory(at: resolverDir, withIntermediateDirectories: true)
    }

    let contents = """
    domain test
    nameserver 127.0.0.1
    port 5353
    """

    try contents.write(to: vesselResolverFile, atomically: true, encoding: .utf8)

    print("Successfully configured /etc/resolver/test for Magic DNS.")
} catch {
    print("Failed to configure /etc/resolver/test: \(error)")
    exit(1)
}
exit(0)
