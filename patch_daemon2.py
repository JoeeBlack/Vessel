import re

cd_path = "Sources/Vessel/ContainerDaemon.swift"
with open(cd_path, "r") as f:
    cd = f.read()

# Replace Task { in daemon if there are any
print("Tasks in CD: ", cd.count("Task {"))
print("DispatchQueue in CD: ", cd.count("DispatchQueue"))

# Look for vmm.start() or container.start() to wrap in dispatch queue?
# No, "w Vessel, podczas odpalania zadań w tle (np. odpytywanie o logi, proces daemona orkiestrującego), obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background."
# Wait, ContainerViewModel is where Tasks are used.
