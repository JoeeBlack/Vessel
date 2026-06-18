import re

# 1. AppIntents.swift fixes
content = open('Sources/Vessel/AppIntents.swift').read()
content = content.replace('public static var title: LocalizedStringResource', 'public static let title: LocalizedStringResource')
content = content.replace('public static var description = IntentDescription', 'public static let description = IntentDescription')
open('Sources/Vessel/AppIntents.swift', 'w').write(content)

# 2. BookmarkManager.swift fixes
content = open('Sources/Vessel/BookmarkManager.swift').read()
content = content.replace('public class BookmarkManager {', 'public final class BookmarkManager: @unchecked Sendable {')
open('Sources/Vessel/BookmarkManager.swift', 'w').write(content)

# 3. ContainerDaemon.swift fixes
content = open('Sources/Vessel/ContainerDaemon.swift').read()
content = content.replace('linux.interfaces?.first?.address', 'linux.interfaces.first?.address')
content = content.replace('linuxContainer.interfaces?.first?.address', 'linuxContainer.interfaces.first?.address')
content = content.replace('container.interfaces?.first?.address', 'container.interfaces.first?.address')
content = content.replace('func debugLog(_ msg: String) {', '@Sendable func debugLog(_ msg: String) {')
open('Sources/Vessel/ContainerDaemon.swift', 'w').write(content)

# 4. ComposeParser.swift fixes
content = open('Sources/Vessel/ComposeParser.swift').read()
content = content.replace('let parser = try Yams.Parser(yaml: yaml)\n        var aliasCount = 0\n        for event in parser {', 'var parser = try Yams.Parser(yaml: yaml)\n        var aliasCount = 0\n        while let event = try? parser.next() {')
open('Sources/Vessel/ComposeParser.swift', 'w').write(content)

print("Applied fixes")
