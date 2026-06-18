import re

content = open('Sources/Vessel/ContainersListView.swift').read()

# Fix the extra braces around line 316
old_code = """                            ForEach(forwards, id: \.hostPort) { pf in
                                PortForwardLinkView(pf: pf)
                            }
                            }
                        }
                    }
                } else {"""
new_code = """                            ForEach(forwards, id: \.hostPort) { pf in
                                PortForwardLinkView(pf: pf)
                            }
                        }
                    } else {"""

content = content.replace(old_code, new_code)
open('Sources/Vessel/ContainersListView.swift', 'w').write(content)
print("Fixed ContainersListView extra braces")
