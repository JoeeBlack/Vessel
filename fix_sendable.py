import re

# 1. ContainerViewModel
content = open('Sources/Vessel/ContainerViewModel.swift').read()
content = content.replace('public class ContainerViewModel {', 'public class ContainerViewModel: @unchecked Sendable {')
open('Sources/Vessel/ContainerViewModel.swift', 'w').write(content)

# 2. XPCServer
content = open('Sources/Vessel/XPCServer.swift').read()
content = content.replace('class VesselXPCServer: NSObject, VesselXPCProtocol {', 'class VesselXPCServer: NSObject, VesselXPCProtocol, @unchecked Sendable {')
open('Sources/Vessel/XPCServer.swift', 'w').write(content)

print("Applied @unchecked Sendable")
