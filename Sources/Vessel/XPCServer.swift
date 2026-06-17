import Foundation
import VesselXPC

class VesselXPCServer: NSObject, VesselXPCProtocol {
    private let daemon = ContainerDaemon()

    func ps(reply: @escaping (String) -> Void) {
        Task {
            do {
                let containers = try await daemon.fetchContainers()

                // Format output like `docker ps`
                var output = "CONTAINER ID   IMAGE          COMMAND   CREATED        STATUS          PORTS     NAMES\n"

                for container in containers {
                    let id = String(container.id.prefix(12))
                    let image = container.image
                    let command = "\"\"" // simplified
                    let created = "Unknown" // Assuming no created date available easily, or mock it
                    let status = container.status.rawValue
                    let ports = "" // Mock ports
                    let name = container.name

                    let idPadded = id.padding(toLength: 15, withPad: " ", startingAt: 0)
                    let imagePadded = image.padding(toLength: 15, withPad: " ", startingAt: 0)
                    let commandPadded = String(command.prefix(10)).padding(toLength: 10, withPad: " ", startingAt: 0)
                    let createdPadded = created.padding(toLength: 15, withPad: " ", startingAt: 0)
                    let statusPadded = status.padding(toLength: 16, withPad: " ", startingAt: 0)
                    let portsPadded = ports.padding(toLength: 10, withPad: " ", startingAt: 0)
                    let namePadded = name

                    output += "\(idPadded)\(imagePadded)\(commandPadded)\(createdPadded)\(statusPadded)\(portsPadded)\(namePadded)\n"
                }

                reply(output)
            } catch {
                reply("Error: \(error.localizedDescription)")
            }
        }
    }
}

class VesselXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        newConnection.exportedObject = VesselXPCServer()
        newConnection.resume()
        return true
    }
}
