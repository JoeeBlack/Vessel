import re

# AppIntents.swift
content = open('Sources/Vessel/AppIntents.swift').read()
content = content.replace('public static var typeDisplayRepresentation', 'public static let typeDisplayRepresentation')
content = content.replace('public static var defaultQuery', 'public static let defaultQuery')
open('Sources/Vessel/AppIntents.swift', 'w').write(content)

# ComposeParser.swift
content = open('Sources/Vessel/ComposeParser.swift').read()
content = content.replace('try? parser.next()', 'try parser.nextEvent()')
open('Sources/Vessel/ComposeParser.swift', 'w').write(content)

print("Fixed")
