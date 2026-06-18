import re

# Fix PodCardView.swift
content = open('Sources/Vessel/PodCardView.swift').read()
content = content.replace('Material.ultraThin\n                AppTheme.cardBackground', 'Rectangle().fill(Material.ultraThin)\n                AppTheme.cardBackground')
open('Sources/Vessel/PodCardView.swift', 'w').write(content)

# Fix ContainersListView.swift
content = open('Sources/Vessel/ContainersListView.swift').read()
old_code = '''                            ForEach(forwards, id: \.hostPort) { pf in
                                if let url = URL(string: "http://localhost:\(pf.hostPort)") {
                                    Link("\(pf.hostPort):\(pf.containerPort)", destination: url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                        .underline()
                                        .help("Open in Browser")
                                        .accessibilityLabel("Open localhost:\(pf.hostPort) in Browser")
                                } else {'''

new_code = '''                            ForEach(forwards, id: \.hostPort) { pf in
                                let urlString = "http://localhost:\(pf.hostPort)"
                                let linkText = "\(pf.hostPort):\(pf.containerPort)"
                                if let url = URL(string: urlString) {
                                    Link(linkText, destination: url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                        .underline()
                                        .help("Open in Browser")
                                        .accessibilityLabel("Open \(urlString) in Browser")
                                } else {'''

content = content.replace(old_code, new_code)
open('Sources/Vessel/ContainersListView.swift', 'w').write(content)

print('Done applying fixes.')
