import re

content = open('build_dmg.sh').read()
content = content.replace('swift build -c release -Xswiftc -whole-module-optimization -Xlinker -dead_strip', 'swift build -c release -Xswiftc -strict-concurrency=minimal -Xswiftc -whole-module-optimization -Xlinker -dead_strip')
content = content.replace('swift build -c release --product vcctl -Xswiftc -whole-module-optimization -Xlinker -dead_strip', 'swift build -c release --product vcctl -Xswiftc -strict-concurrency=minimal -Xswiftc -whole-module-optimization -Xlinker -dead_strip')

open('build_dmg.sh', 'w').write(content)
print("Fixed script")
