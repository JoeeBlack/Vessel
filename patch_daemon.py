import re

cd_path = "Sources/Vessel/ContainerDaemon.swift"
with open(cd_path, "r") as f:
    cd = f.read()

# Models init
cd = cd.replace("rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, rootfsSize: vessel.rootfsSize,", "rosettaEnabled: vessel.rosettaEnabled, networkingEnabled: vessel.networkingEnabled, isBackground: vessel.isBackground, rootfsSize: vessel.rootfsSize,")

cd = cd.replace("rosettaEnabled: true,\n                networkingEnabled: true,\n                rootfsSize: \"8GB\",", "rosettaEnabled: true,\n                networkingEnabled: true,\n                isBackground: false,\n                rootfsSize: \"8GB\",")

cd = cd.replace("rosettaEnabled: $0.rosettaEnabled, networkingEnabled: $0.networkingEnabled, rootfsSize: $0.rootfsSize,", "rosettaEnabled: $0.rosettaEnabled, networkingEnabled: $0.networkingEnabled, isBackground: $0.isBackground, rootfsSize: $0.rootfsSize,")

cd = cd.replace("public func start(containerId: String, imageReference: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, cpus: Int = 2", "public func start(containerId: String, imageReference: String, name: String, rootfsSizeGB: Double, rosetta: Bool, networking: Bool, isBackground: Bool = false, cpus: Int = 2")

cd = cd.replace("rosettaEnabled: rosetta,\n            networkingEnabled: networking,\n            rootfsSize:", "rosettaEnabled: rosetta,\n            networkingEnabled: networking,\n            isBackground: isBackground,\n            rootfsSize:")

# 4 instances to replace:
cd = cd.replace("DispatchQueue(label: \"...\", qos: .utility)", "DispatchQueue(label: \"com.vessel.daemon\", qos: .utility)")
with open(cd_path, "w") as f:
    f.write(cd)
