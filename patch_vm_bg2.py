import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

# For `startShell` and general daemon task delegation
# `daemon.start`, `daemon.stop`, `daemon.delete` should also be wrapped?
# prompt: "W Vessel, podczas odpalania zadań w tle (np. odpytywanie o logi, proces daemona orkiestrującego), obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background."

# If we wrap the VM process itself... wait, the VM itself is run by Virtualization.framework in the daemon.
# Let's verify `ContainerDaemon.swift` and where we create the VZVirtualMachine.
# `container.create()` and `container.start()` inside `ContainerDaemon.swift`.
