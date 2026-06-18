import re

content = open('Sources/Vessel/ContainersListView.swift').read()
old_code = '''                            ForEach(forwards, id: \.hostPort) { pf in
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

new_code = '''                            ForEach(forwards, id: \.hostPort) { pf in
                                let urlString = "http://localhost:\(pf.hostPort)"
                                let linkText = "\(pf.hostPort):\(pf.containerPort)"
                                let accLabel = "Open " + urlString + " in Browser"
                                if let url = URL(string: urlString) {
                                    Link(linkText, destination: url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                        .underline()
                                        .help("Open in Browser")
                                        .accessibilityLabel(Text(accLabel))
                                } else {'''

content = content.replace(old_code, new_code)
open('Sources/Vessel/ContainersListView.swift', 'w').write(content)

print('Done applying fixes.')
