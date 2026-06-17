import re

cd_path = "Sources/Vessel/ContainerDaemon.swift"
with open(cd_path, "r") as f:
    cd = f.read()

# Replace `.default` with `.utility` for daemon orchestrator
cd = cd.replace("isBackground ? .background : .default", "isBackground ? .background : .utility")

with open(cd_path, "w") as f:
    f.write(cd)
