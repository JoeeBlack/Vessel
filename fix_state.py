import re

with open("Sources/Vessel/ContentView.swift", "r") as f:
    content = f.read()

content = content.replace("@State private var", "@SwiftUI.State private var")
content = content.replace("@State var", "@SwiftUI.State var")

with open("Sources/Vessel/ContentView.swift", "w") as f:
    f.write(content)

