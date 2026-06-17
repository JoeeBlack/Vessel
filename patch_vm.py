import re

cvm_path = "Sources/Vessel/ContainerViewModel.swift"
with open(cvm_path, "r") as f:
    cvm = f.read()

# Modify `streamLogs` and `subscribeToStats` to use DispatchQueue

# 1. Background execution using Task with priority if possible?
# "obowiązkowo owijamy kod w klasy DispatchQueue(label: "...", qos: .utility) lub .background"

# Wait, `isBackground` flag needs to be checked.
# "Gdy kontener jest oznaczony przez dewelopera jako "Zadanie w tle" (np. prosta baza Redis w trybie czuwania), jego wątki wirtualnego CPU są systemowo relegowane przez macOS wyłącznie na klastry E-Cores."

# Is there an API for Virtualization framework to set this? VZVirtualMachineConfiguration? CPU count?
