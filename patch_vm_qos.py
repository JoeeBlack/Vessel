import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

# Make sure we use DispatchQueue for streamLogs and stats
cvm = cvm.replace("let qos: DispatchQoS = isBg ? .background : .utility", "let qos: DispatchQoS = isBg ? .background : .utility")

with open(cvm_path, "w") as f:
    f.write(cvm)
