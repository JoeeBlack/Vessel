import re

content = open('Sources/Vessel/ContainersListView.swift').read()

old_code = """                            ForEach(forwards, id: \.hostPort) { pf in
                                if let url = URL(string: "http://localhost:\(pf.hostPort)") {
                                    Link("\(pf.hostPort):\(pf.containerPort)", destination: url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                        .underline()
                                        .help("Open in Browser")
                                        .accessibilityLabel("Open localhost:\(pf.hostPort) in Browser")
                                } else {
                                    Text("\(pf.hostPort):\(pf.containerPort)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.accentBlue)
                                }
                            }"""

new_code = """                            ForEach(forwards, id: \.hostPort) { pf in
                                PortForwardLinkView(pf: pf)
                            }"""

content = content.replace(old_code, new_code)

view_code = """

struct PortForwardLinkView: View {
    let pf: VesselPortForward
    var body: some View {
        let urlString = "http://localhost:\\(pf.hostPort)"
        let linkText = "\\(pf.hostPort):\\(pf.containerPort)"
        if let url = URL(string: urlString) {
            Link(linkText, destination: url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.accentBlue)
                .underline()
                .help("Open in Browser")
                .accessibilityLabel(Text("Open localhost:\\(pf.hostPort) in Browser"))
        } else {
            Text(linkText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.accentBlue)
        }
    }
}
"""
content = content + view_code

open('Sources/Vessel/ContainersListView.swift', 'w').write(content)
print("Done")
