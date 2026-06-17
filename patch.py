import re
import os

# 1. Update Models.swift
models_path = "Sources/Vessel/Models.swift"
with open(models_path, "r") as f:
    models = f.read()

models = models.replace("public let networkingEnabled: Bool\n    public let rootfsSize: String", "public let networkingEnabled: Bool\n    public let isBackground: Bool\n    public let rootfsSize: String")
models = models.replace("rosettaEnabled: Bool = false, networkingEnabled: Bool = true, rootfsSize: String", "rosettaEnabled: Bool = false, networkingEnabled: Bool = true, isBackground: Bool = false, rootfsSize: String")
models = models.replace("self.networkingEnabled = networkingEnabled\n        self.rootfsSize = rootfsSize", "self.networkingEnabled = networkingEnabled\n        self.isBackground = isBackground\n        self.rootfsSize = rootfsSize")
models = models.replace("rosettaEnabled, networkingEnabled, rootfsSize", "rosettaEnabled, networkingEnabled, isBackground, rootfsSize")
models = models.replace("try container.encode(networkingEnabled, forKey: .networkingEnabled)\n        try container.encode(rootfsSize, forKey: .rootfsSize)", "try container.encode(networkingEnabled, forKey: .networkingEnabled)\n        try container.encode(isBackground, forKey: .isBackground)\n        try container.encode(rootfsSize, forKey: .rootfsSize)")
models = models.replace("self.networkingEnabled = try container.decode(Bool.self, forKey: .networkingEnabled)\n        self.rootfsSize = try container.decode(String.self, forKey: .rootfsSize)", "self.networkingEnabled = try container.decode(Bool.self, forKey: .networkingEnabled)\n        self.isBackground = try container.decodeIfPresent(Bool.self, forKey: .isBackground) ?? false\n        self.rootfsSize = try container.decode(String.self, forKey: .rootfsSize)")

with open(models_path, "w") as f:
    f.write(models)


# 2. Update CreateContainerView.swift
ccv_path = "Sources/Vessel/CreateContainerView.swift"
with open(ccv_path, "r") as f:
    ccv = f.read()

ccv = ccv.replace("@State private var enableNetworking: Bool = true\n    ", "@State private var enableNetworking: Bool = true\n    @State private var isBackground: Bool = false\n    ")
ccv = ccv.replace("var onCreate: (_ name: String, _ image: String, _ rootfs: Double, _ rosetta: Bool, _ networking: Bool, _ cpus: Int, _ memoryGB: Double, _ envVars: [String: String], _ volumes: [(host: String, container: String)], _ portForwards: [(hostPort: Int, containerPort: Int)], _ domain: VesselDomain) -> Void", "var onCreate: (_ name: String, _ image: String, _ rootfs: Double, _ rosetta: Bool, _ networking: Bool, _ isBackground: Bool, _ cpus: Int, _ memoryGB: Double, _ envVars: [String: String], _ volumes: [(host: String, container: String)], _ portForwards: [(hostPort: Int, containerPort: Int)], _ domain: VesselDomain) -> Void")
ccv = ccv.replace("onCreate(containerName, selectedImage, rootfsSize, enableRosetta, enableNetworking, Int(cpuCount), memoryGB, envMap, vMap, pMap, selectedDomain)", "onCreate(containerName, selectedImage, rootfsSize, enableRosetta, enableNetworking, isBackground, Int(cpuCount), memoryGB, envMap, vMap, pMap, selectedDomain)")

toggle_networking = """                        Toggle(isOn: $enableNetworking) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Networking")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Attach a dedicated Netlink interface.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppTheme.accentBlue)"""

toggle_bg = """                        Toggle(isOn: $isBackground) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Background Task (E-Cores)")
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Delegate workload to efficiency cores to save power and keep system quiet.")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(AppTheme.accentBlue)"""

ccv = ccv.replace(toggle_networking, toggle_networking + "\n                        \n" + toggle_bg)

with open(ccv_path, "w") as f:
    f.write(ccv)

# 3. Update ContentView.swift
cv_path = "Sources/Vessel/ContentView.swift"
with open(cv_path, "r") as f:
    cv = f.read()

cv = cv.replace("CreateContainerView { name, image, rootfs, rosetta, networking, cpus, memoryGB, envVars, volumes, portForwards, domain in", "CreateContainerView { name, image, rootfs, rosetta, networking, isBackground, cpus, memoryGB, envVars, volumes, portForwards, domain in")
cv = cv.replace("await viewModel.createContainer(name: name, image: image, rootfsSizeGB: rootfs, rosetta: rosetta, networking: networking, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: vesselVolumes, portForwards: vesselForwards, domain: domain)", "await viewModel.createContainer(name: name, image: image, rootfsSizeGB: rootfs, rosetta: rosetta, networking: networking, isBackground: isBackground, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: vesselVolumes, portForwards: vesselForwards, domain: domain)")

with open(cv_path, "w") as f:
    f.write(cv)

# 4. Update ContainerViewModel.swift
cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

cvm = cvm.replace("networking: Bool, cpus: Int", "networking: Bool, isBackground: Bool, cpus: Int")
cvm = cvm.replace("networking: networking, cpus: cpus", "networking: networking, isBackground: isBackground, cpus: cpus")
cvm = cvm.replace("rosettaEnabled: false, networkingEnabled: true, rootfsSize", "rosettaEnabled: false, networkingEnabled: true, isBackground: false, rootfsSize")
cvm = cvm.replace("rosettaEnabled: false, networkingEnabled: true, cpus", "rosettaEnabled: false, networkingEnabled: true, isBackground: false, cpus")
cvm = cvm.replace("status: .creating, portForwards:", "status: .creating, isBackground: isBackground, portForwards:")

with open(cvm_path, "w") as f:
    f.write(cvm)
