import re

cd_path = "Sources/Vessel/ContainerDaemon.swift"
with open(cd_path, "r") as f:
    cd = f.read()

# For start(containerId: imageReference: ...)
find_str = """        debugLog("Calling container.create()...")
        try await container.create()
        debugLog("Calling container.start()...")
        try await container.start()
        debugLog("Container started successfully!")"""

replace_str = """        debugLog("Calling container.create()...")
        let qos: DispatchQoS = isBackground ? .background : .default
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "com.vessel.daemon.vm", qos: qos).async {
                Task {
                    do {
                        try await container.create()
                        debugLog("Calling container.start()...")
                        try await container.start()
                        debugLog("Container started successfully!")
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }"""

cd = cd.replace(find_str, replace_str)


# For start(containerId:)
# there are two parts:
# 1. try await container.create() inside if linux == nil
find_str2 = """            debugLog("Calling container.create()...")
            try await container.create()
            linux = container
        }

        // Security: Avoid force unwrap to prevent application crash if the container fails to initialize.
        guard let linuxContainer = linux else {
            throw NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Linux container"])
        }

        debugLog("Calling linuxContainer.start()...")
        try await linuxContainer.start()
        debugLog("linuxContainer.start() succeeded!")"""

replace_str2 = """            debugLog("Calling container.create()...")
            let qosCreate: DispatchQoS = vessel.isBackground ? .background : .default
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue(label: "com.vessel.daemon.vm", qos: qosCreate).async {
                    Task {
                        do {
                            try await container.create()
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            linux = container
        }

        // Security: Avoid force unwrap to prevent application crash if the container fails to initialize.
        guard let linuxContainer = linux else {
            throw NSError(domain: "Vessel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Linux container"])
        }

        debugLog("Calling linuxContainer.start()...")
        let qosStart: DispatchQoS = vessel.isBackground ? .background : .default
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "com.vessel.daemon.vm", qos: qosStart).async {
                Task {
                    do {
                        try await linuxContainer.start()
                        debugLog("linuxContainer.start() succeeded!")
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }"""

cd = cd.replace(find_str2, replace_str2)


# For `startStatsStream` and `execShell` and `streamLogs` ?
# The prompt: "podczas odpalania zadań w tle (np. odpytywanie o logi, proces daemona orkiestrującego), obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background."
# We should do this in ContainerViewModel where we call them!

with open(cd_path, "w") as f:
    f.write(cd)
