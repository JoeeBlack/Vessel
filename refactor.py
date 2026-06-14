import re
import os

with open("Sources/Vessel/ContainerDaemon.swift", "r") as f:
    content = f.read()

# 1. ImageStore replacements
content = content.replace("let store = ImageStore.default", """let storePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/images")
        let contentPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel/content")
        let contentStore = try LocalContentStore(path: contentPath)
        let store = try ImageStore(path: storePath, contentStore: contentStore)""")

# 2. ActivePod replacements
content = content.replace("var linuxPod: LinuxPod?", "var linuxContainers: [String: LinuxContainer] = [:]")
content = content.replace("linuxPod: nil", "linuxContainers: [:]")
content = content.replace("activePod.linuxPod", "activePod.linuxContainers")

with open("Sources/Vessel/ContainerDaemon.swift", "w") as f:
    f.write(content)

