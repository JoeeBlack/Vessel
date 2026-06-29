import Foundation
import Security
import VesselXPC

class VesselDaemonXPC: NSObject, VesselXPCProtocol {
    private let daemon = ContainerDaemon()

    func ps(reply: @escaping (String) -> Void) {
        reply("vesseld is running securely")
    }

    func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void) {
        reply("vesseld cannot wake container: not implemented", nil)
    }

    func scanImage(reference: String, reply: @escaping (Data?, Error?) -> Void) {
        reply(nil, NSError(domain: "VesselDaemonXPC", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented in daemon"]))
    }

    func sendCommand(command: String, payload: Data, reply: @escaping (Data?, Error?) -> Void) {
        Task {
            do {
                let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]

                switch command {
                case "fetchActiveContainers":
                    let containers = try await daemon.fetchActiveContainers()
                    reply(try JSONEncoder().encode(containers), nil)
                case "fetchActiveWorkloads":
                    let workloads = try await daemon.fetchActiveWorkloads()
                    reply(try JSONEncoder().encode(workloads), nil)
                case "getContainerIP":
                    if let id = dict?["id"] as? String, let ip = daemon.getContainerIP(containerId: id) {
                        reply(try JSONSerialization.data(withJSONObject: ["ip": ip]), nil)
                    } else {
                        reply(Data(), nil)
                    }
                case "fetchDomainRules":
                    let rules = daemon.fetchDomainRules()
                    reply(try JSONEncoder().encode(rules), nil)
                case "addDomainRule":
                    if let d = dict,
                       let jsonData = try? JSONSerialization.data(withJSONObject: d),
                       let rule = try? JSONDecoder().decode(DomainRule.self, from: jsonData) {
                        daemon.addDomainRule(rule)
                    }
                    reply(Data(), nil)
                case "removeDomainRule":
                    if let idStr = dict?["id"] as? String, let uuid = UUID(uuidString: idStr) {
                        daemon.removeDomainRule(id: uuid)
                    }
                    reply(Data(), nil)
                case "startPod":
                    if let path = dict?["yamlPath"] as? String {
                        try await daemon.startPod(yamlPath: URL(fileURLWithPath: path))
                    }
                    reply(Data(), nil)
                case "startFull":
                    if let d = dict,
                       let id = d["containerId"] as? String,
                       let image = d["imageReference"] as? String,
                       let name = d["name"] as? String,
                       let rootfs = d["rootfsSizeGB"] as? Double,
                       let rosetta = d["rosetta"] as? Bool,
                       let networking = d["networking"] as? Bool,
                       let cpus = d["cpus"] as? Int,
                       let memory = d["memoryGB"] as? Double,
                       let isBg = d["isBackground"] as? Bool,
                       let envVars = d["envVars"] as? [String: String],
                       let vols = d["volumes"],
                       let pfs = d["portForwards"],
                       let domainRaw = d["domain"] {

                        let vData = try JSONSerialization.data(withJSONObject: vols)
                        let pfData = try JSONSerialization.data(withJSONObject: pfs)
                        let dData = try JSONSerialization.data(withJSONObject: domainRaw)

                        let volumes = try JSONDecoder().decode([VesselVolume].self, from: vData)
                        let portForwards = try JSONDecoder().decode([VesselPortForward].self, from: pfData)
                        let domain = try JSONDecoder().decode(VesselDomain.self, from: dData)

                        try await daemon.start(containerId: id, imageReference: image, name: name, rootfsSizeGB: rootfs, rosetta: rosetta, networking: networking, isBackground: isBg, cpus: cpus, memoryGB: memory, envVars: envVars, volumes: volumes, portForwards: portForwards, domain: domain)
                    }
                    reply(Data(), nil)
                case "start":
                    if let id = dict?["id"] as? String {
                        try await daemon.start(containerId: id)
                    }
                    reply(Data(), nil)
                case "listFiles":
                    if let id = dict?["id"] as? String, let path = dict?["path"] as? String {
                        let files = try await daemon.listFiles(in: path, containerId: id)
                        reply(try JSONSerialization.data(withJSONObject: ["files": files]), nil)
                    }
                case "downloadFile":
                    if let id = dict?["id"] as? String, let path = dict?["path"] as? String, let dest = dict?["dest"] as? String {
                        try await daemon.downloadFile(containerId: id, path: path, to: URL(fileURLWithPath: dest))
                    }
                    reply(Data(), nil)
                case "uploadFile":
                    if let id = dict?["id"] as? String, let source = dict?["source"] as? String, let dest = dict?["dest"] as? String {
                        try await daemon.uploadFile(containerId: id, from: URL(fileURLWithPath: source), to: dest)
                    }
                    reply(Data(), nil)
                case "pauseAll":
                    try await daemon.pauseAll()
                    reply(Data(), nil)
                case "resumeAll":
                    try await daemon.resumeAll()
                    reply(Data(), nil)
                case "stop":
                    if let id = dict?["id"] as? String, let force = dict?["force"] as? Bool {
                        try await daemon.stop(containerId: id, force: force)
                    }
                    reply(Data(), nil)
                case "delete":
                    if let id = dict?["id"] as? String {
                        try await daemon.delete(containerId: id)
                    }
                    reply(Data(), nil)
                case "fetchImages":
                    let images = try await daemon.fetchImages()
                    reply(try JSONEncoder().encode(images), nil)
                case "deleteImage":
                    if let ref = dict?["ref"] as? String {
                        try await daemon.deleteImage(reference: ref)
                    }
                    reply(Data(), nil)
                default:
                    reply(nil, NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Command not found: \(command)"]))
                }
            } catch {
                reply(nil, error)
            }
        }
    }

    func openStream(command: String, payload: Data, delegate: VesselXPCStreamDelegate) {
        Task {
            do {
                let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]

                switch command {
                case "startStatsStream":
                    if let id = dict?["id"] as? String {
                        let stream = try await daemon.startStatsStream(containerId: id)
                        for await stat in stream {
                            if let data = try? JSONEncoder().encode(stat) {
                                delegate.onEvent(payload: data)
                            }
                        }
                        delegate.onComplete(error: nil)
                    }
                case "streamLogs":
                    if let id = dict?["id"] as? String {
                        let stream = daemon.streamLogs(for: id)
                        for await log in stream {
                            if let data = log.data(using: .utf8) {
                                delegate.onEvent(payload: data)
                            }
                        }
                        delegate.onComplete(error: nil)
                    }
                case "pullImage":
                    if let ref = dict?["ref"] as? String {
                        try await daemon.pullImage(reference: ref) { progress in
                            if let data = try? JSONSerialization.data(withJSONObject: ["progress": progress, "finished": false]) {
                                delegate.onEvent(payload: data)
                            }
                        }
                        if let data = try? JSONSerialization.data(withJSONObject: ["progress": 1.0, "finished": true]) {
                            delegate.onEvent(payload: data)
                            delegate.onComplete(error: nil)
                        }
                    }
                default:
                    delegate.onComplete(error: NSError(domain: "VesselDaemonXPC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stream command not found: \(command)"]))
                }
            } catch {
                delegate.onComplete(error: error)
            }
        }
    }
}

class VesselDaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        var token = newConnection.auditToken
        guard let secTask = SecTaskCreateWithAuditToken(nil, token) else {
            print("Failed to create SecTask from audit token.")
            return false
        }

        guard let identifier = SecTaskCopySigningIdentifier(secTask, nil) as String?, identifier == "com.vessel.app" else {
            print("Rejecting connection from unauthorized client.")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: VesselXPCProtocol.self)
        newConnection.exportedObject = VesselDaemonXPC()
        newConnection.resume()
        return true
    }
}

let delegate = VesselDaemonDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
