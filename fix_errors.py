import re
import os

with open("Sources/Vessel/ContentView.swift", "r") as f:
    content = f.read()

# Fix LocalContentStore scope issue
if "import ContainerizationOCI" not in content:
    content = content.replace("import Containerization\n", "import Containerization\nimport ContainerizationOCI\n")

with open("Sources/Vessel/ContentView.swift", "w") as f:
    f.write(content)

with open("Sources/Vessel/ContainerDaemon.swift", "r") as f:
    content = f.read()

# 1. @unchecked Sendable ContainerDaemon
content = content.replace("public class ContainerDaemon {", "public final class ContainerDaemon: @unchecked Sendable {")

# 2. ContainerDaemon.swift: execShell
exec_shell_old = """        var config = LinuxProcessConfiguration()
        config.arguments = ["/bin/sh", "-l"]
        config.terminal = true
        config.stdin = stdin
        config.stdout = stdout
        config.stderr = nil
        config.environmentVariables = [
            "TERM=xterm-256color",
            "HOME=/root",
            "USER=root"
        ]
        
        let execId = "shell-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config)"""

exec_shell_new = """        let config = ContainerizationOCI.Process(
            args: ["/bin/sh", "-l"],
            env: [
                "TERM=xterm-256color",
                "HOME=/root",
                "USER=root"
            ],
            terminal: true
        )
        let execId = "shell-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config, stdin: stdin, stdout: stdout, stderr: nil)"""
content = content.replace(exec_shell_old, exec_shell_new)

# 3. streamStats
stream_stats_old = """        var config = Containerization.LinuxProcessConfiguration()
        // Run a lightweight non-interactive background loop to stream stats
        config.arguments = ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"]
        config.terminal = false
        
        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        config.stdout = readerWriter
        
        let execId = "stats-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config)"""

stream_stats_new = """        let readerWriter = StatsProcessReaderWriter(continuation: continuation)
        let config = ContainerizationOCI.Process(
            args: ["sh", "-c", "while true; do cat /proc/stat; echo '---MEM---'; cat /proc/meminfo; echo '---LOAD---'; cat /proc/loadavg; echo '---UPTIME---'; cat /proc/uptime; echo '---END---'; sleep 1; done"],
            terminal: false
        )
        let execId = "stats-\\(UUID().uuidString)"
        let process = try await linux.exec(execId, configuration: config, stdout: readerWriter)"""
content = content.replace(stream_stats_old, stream_stats_new)

# 4. stop(containerId:)
stop_old = """        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxContainers {
                try? await linuxPod.stop()
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .stopped, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxContainers: activePod.linuxContainers)
            savePods()
            return
        }"""
stop_new = """        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            let pod = activePod.pod
            let updatedPod = VesselPod(id: pod.id, name: pod.name, status: .stopped, containers: pod.containers, cpus: pod.cpus, memoryGB: pod.memoryGB)
            activePods[containerId] = ActivePod(pod: updatedPod, linuxContainers: activePod.linuxContainers)
            savePods()
            return
        }"""
content = content.replace(stop_old, stop_new)

# 5. delete(containerId:)
delete_old = """        if let activePod = activePods[containerId] {
            if let linuxPod = activePod.linuxContainers {
                try? await linuxPod.stop()
            }
            activePods.removeValue(forKey: containerId)
            savePods()
            return
        }"""
delete_new = """        if let activePod = activePods[containerId] {
            for (_, container) in activePod.linuxContainers {
                try? await container.stop()
            }
            activePods.removeValue(forKey: containerId)
            savePods()
            return
        }"""
content = content.replace(delete_old, delete_new)

# 6. progress event
content = content.replace("case .addSize(let size):", "case .add(let size):")

# 7. config(for: .current) and pull: false
content = content.replace("image.config(for: .current).config", "image.config().config")
content = content.replace("store.get(reference: normalize(reference: vessel.image), pull: false)", "store.get(reference: normalize(reference: vessel.image))")

# 8. defaultMounts()
content = content.replace("LinuxContainer.defaultMounts()", "LinuxContainer.createDefaultMounts()")

# 9. let network
content = content.replace("if let network = network {", "if var network = network {")

with open("Sources/Vessel/ContainerDaemon.swift", "w") as f:
    f.write(content)

