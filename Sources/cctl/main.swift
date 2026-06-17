import Foundation
import ArgumentParser
import VesselXPC

@main
struct Cctl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cctl",
        abstract: "A drop-in replacement CLI for docker using Vessel backend via XPC.",
        subcommands: [PS.self]
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
            exit(1)
        } as! VesselXPCProtocol

        let semaphore = DispatchSemaphore(value: 0)
        proxy.ps { output in
            print(output, terminator: "")
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + 5.0)
        if result == .timedOut {
            print("Error: Timed out waiting for response from Vessel daemon.")
            exit(1)
        }
    }
}
