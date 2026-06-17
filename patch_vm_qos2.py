import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

# For `startShell`, the process itself is created by daemon.execShell. We don't have a background task looping continuously here, but we could wrap `daemon.execShell` in DispatchQueue.
# Same for any other long-running operations.

with open(cvm_path, "w") as f:
    f.write(cvm)
