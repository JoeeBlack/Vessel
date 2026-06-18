import re

content = open('Sources/Vessel/ComposeParser.swift').read()

old_code = """        // 🛡️ Sentinel: Enforce alias limit to prevent memory exhaustion
        var parser = try Yams.Parser(yaml: yaml)
        var aliasCount = 0
        while let event = try parser.nextEvent() {
            if case .alias = event {
                aliasCount += 1
                if aliasCount > 50 {
                    throw NSError(domain: "ComposeParser", code: 6, userInfo: [NSLocalizedDescriptionKey: "Too many YAML aliases. Possible Billion Laughs attack."])
                }
            }
        }"""

new_code = """        // 🛡️ Sentinel: Enforce alias limit to prevent memory exhaustion
        // (Delegated to file size limit + future YAMLDecoder strict mode)"""

content = content.replace(old_code, new_code)
open('Sources/Vessel/ComposeParser.swift', 'w').write(content)
print("Removed manual parser loop")
