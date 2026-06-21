import Foundation
import ArgumentParser
import VesselXPC

@main
struct Cctl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cctl",
        abstract: "A drop-in replacement CLI for docker using Vessel backend via XPC.",
        subcommands: [PS.self, EnableWake.self, DisableWake.self, WakeProxy.self]
    )
}

struct PS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers"
    )

    func run() throws {
        let connection = NSXPCConnection(machServiceName: "com.vessel.cctl.xpc", options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("Failed to connect to Vessel daemon: \(error.localizedDescription)")
            Foundation.exit(1)
        } as! VesselXPCProtocol

        let semaphore = DispatchSemaphore(value: 0)
        proxy.ps { output in
            print(output, terminator: "")
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 5.0)
        if result == .timedOut {
            print("Error: Timed out waiting for response from Vessel daemon.")
            Foundation.exit(1)
        }
    }
}

struct EnableWake: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable-wake",
        abstract: "Enable socket activation for a container on a specific host port."
    )

    @Argument(help: "The ID of the container to wake.")
    var containerId: String

    @Argument(help: "The host port to listen on.")
    var port: Int

    @Argument(help: "The target container port.")
    var targetPort: Int

    func run() throws {
        let label = "com.vessel.wake.\(containerId).\(port)"
        let plistPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Applications/Vessel.app/Contents/Resources/cctl</string>
                <string>wake-proxy</string>
                <string>\(containerId)</string>
                <string>\(targetPort)</string>
            </array>
            <key>inetdCompatibility</key>
            <dict>
                <key>Wait</key>
                <false/>
            </dict>
            <key>Sockets</key>
            <dict>
                <key>Listeners</key>
                <dict>
                    <key>SockNodeName</key>
                    <string>127.0.0.1</string>
                    <key>SockServiceName</key>
                    <string>\(port)</string>
                    <key>SockType</key>
                    <string>stream</string>
                </dict>
            </dict>
        </dict>
        </plist>
        """

        try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Successfully enabled socket activation on port \(port) for container \(containerId).")
        } else {
            print("Failed to load launchd plist.")
            Foundation.exit(1)
        }
    }
}

struct DisableWake: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable-wake",
        abstract: "Disable socket activation for a container on a specific host port."
    )

    @Argument(help: "The ID of the container.")
    var containerId: String

    @Argument(help: "The host port that was listening.")
    var port: Int

    func run() throws {
        let label = "com.vessel.wake.\(containerId).\(port)"
        let plistPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")

        if FileManager.default.fileExists(atPath: plistPath.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistPath.path]
            try process.run()
            process.waitUntilExit()

            try FileManager.default.removeItem(at: plistPath)
            print("Successfully disabled socket activation on port \(port) for container \(containerId).")
        } else {
            print("Socket activation not found for container \(containerId) on port \(port).")
        }
    }
}

struct WakeProxy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wake-proxy",
        abstract: "Internal proxy invoked by launchd. Do not run manually."
    )

    @Argument(help: "The ID of the container to wake.")
    var containerId: String

    @Argument(help: "The target container port.")
    var targetPort: Int

    func run() throws {
        // Since launchd invokes this with inetdCompatibility wait=false,
        // STDIN (fd 0) and STDOUT (fd 1) are connected to the incoming socket.

        let connection = NSXPCConnection(machServiceName: "com.vessel.cctl.xpc", options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            FileHandle.standardError.write("Failed to connect to Vessel daemon: \(error.localizedDescription)\n".data(using: .utf8)!)
            Foundation.exit(1)
        } as! VesselXPCProtocol

        let semaphore = DispatchSemaphore(value: 0)
        var targetIP: String?
        var wakeError: Error?

        proxy.wakeContainer(containerId: containerId) { ip, error in
            targetIP = ip
            wakeError = error
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 10.0) // Give it time to wake up
        if result == .timedOut {
            FileHandle.standardError.write("Timed out waiting for container to wake.\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        if let error = wakeError {
            FileHandle.standardError.write("Error waking container: \(error.localizedDescription)\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        guard let ip = targetIP else {
            FileHandle.standardError.write("Failed to get container IP.\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        // Now proxy between stdin/stdout and the container's IP/port
        proxyTraffic(targetIP: ip, targetPort: targetPort)
    }

    private func proxyTraffic(targetIP: String, targetPort: Int) {
        var sockaddr_in_addr = sockaddr_in()
        sockaddr_in_addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sockaddr_in_addr.sin_family = sa_family_t(AF_INET)
        sockaddr_in_addr.sin_port = in_port_t(targetPort).bigEndian
        inet_pton(AF_INET, targetIP, &sockaddr_in_addr.sin_addr)

        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        if sockfd < 0 {
            FileHandle.standardError.write("Failed to create socket.\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        let connectResult = withUnsafePointer(to: &sockaddr_in_addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult < 0 {
            FileHandle.standardError.write("Failed to connect to container.\n".data(using: .utf8)!)
            Foundation.exit(1)
        }

        let group = DispatchGroup()
        let globalQueue = DispatchQueue.global()

        // STDIN -> Socket
        let stdinChannel = DispatchIO(type: .stream, fileDescriptor: STDIN_FILENO, queue: globalQueue) { error in
            shutdown(sockfd, SHUT_WR)
        }

        group.enter()
        stdinChannel.read(offset: 0, length: Int.max, queue: globalQueue) { done, data, error in
            if let data = data, !data.isEmpty {
                data.regions.forEach { region in
                    region.withUnsafeBytes { ptr in
                        _ = send(sockfd, ptr.baseAddress, ptr.count, 0)
                    }
                }
            }
            if done || error != 0 {
                stdinChannel.close()
                shutdown(sockfd, SHUT_WR)
                group.leave()
            }
        }

        // Socket -> STDOUT
        let socketChannel = DispatchIO(type: .stream, fileDescriptor: sockfd, queue: globalQueue) { error in
            close(STDOUT_FILENO)
        }

        group.enter()
        socketChannel.read(offset: 0, length: Int.max, queue: globalQueue) { done, data, error in
            if let data = data, !data.isEmpty {
                data.regions.forEach { region in
                    region.withUnsafeBytes { ptr in
                        _ = write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
                    }
                }
            }
            if done || error != 0 {
                socketChannel.close()
                close(STDOUT_FILENO)
                group.leave()
            }
        }

        group.wait()
        close(sockfd)
    }
}
