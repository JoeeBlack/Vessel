import re

with open("Sources/Vessel/Models.swift", "r") as f:
    content = f.read()

content = content.replace("public enum VesselStatus: String, CaseIterable, Codable {", "public enum VesselStatus: String, CaseIterable, Codable, Sendable {")
content = content.replace("public struct VesselVolume: Codable, Hashable {", "public struct VesselVolume: Codable, Hashable, Sendable {")
content = content.replace("public struct VesselPod: Identifiable, Codable, Hashable {", "public struct VesselPod: Identifiable, Codable, Hashable, Sendable {")
content = content.replace("public enum VesselWorkload: Identifiable, Hashable {", "public enum VesselWorkload: Identifiable, Hashable, Sendable {")
content = content.replace("public struct VesselContainer: Identifiable, Codable, Hashable {", "public struct VesselContainer: Identifiable, Codable, Hashable, Sendable {")
content = content.replace("public struct ComposeProject: Codable {", "public struct ComposeProject: Codable, Sendable {")
content = content.replace("public struct ComposeService: Codable {", "public struct ComposeService: Codable, Sendable {")

with open("Sources/Vessel/Models.swift", "w") as f:
    f.write(content)

with open("Sources/Vessel/ContainerViewModel.swift", "r") as f:
    content = f.read()

content = content.replace("    public init() {\n        Task {\n            await fetchInitialWorkloads()\n        }\n    }", "    @MainActor\n    public init() {\n        Task {\n            await fetchInitialWorkloads()\n        }\n    }")

with open("Sources/Vessel/ContainerViewModel.swift", "w") as f:
    f.write(content)
