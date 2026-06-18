import re

content = open('Sources/Vessel/ContainersListView.swift').read()

old_code = """                Material.ultraThin

                AppTheme.cardBackground"""

new_code = """                Rectangle().fill(Material.ultraThin)

                Rectangle().fill(AppTheme.cardBackground)"""

content = content.replace(old_code, new_code)
open('Sources/Vessel/ContainersListView.swift', 'w').write(content)
print("Done fixing Material.ultraThin in ContainersListView")
