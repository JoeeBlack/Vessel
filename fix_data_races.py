import re

# 1. App.swift
content = open('Sources/Vessel/App.swift').read()
content = content.replace("""            Task {
                await viewModel?.pauseAllWorkloads()
            }""", """            if let vm = viewModel {
                Task { await vm.pauseAllWorkloads() }
            }""")
content = content.replace("""            Task {
                await viewModel?.resumeAllWorkloads()
            }""", """            if let vm = viewModel {
                Task { await vm.resumeAllWorkloads() }
            }""")
open('Sources/Vessel/App.swift', 'w').write(content)

# 2. XPCServer.swift
content = open('Sources/Vessel/XPCServer.swift').read()
content = content.replace('func ps(reply: @escaping (String) -> Void) {\n        Task {', 'func ps(reply: @escaping (String) -> Void) {\n        nonisolated(unsafe) let safeReply = reply\n        Task {')
content = content.replace('reply(output)', 'safeReply(output)')
content = content.replace('reply("Error', 'safeReply("Error')

content = content.replace('func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void) {\n        Task {', 'func wakeContainer(containerId: String, reply: @escaping (String?, Error?) -> Void) {\n        nonisolated(unsafe) let safeReply = reply\n        Task {')
content = content.replace('reply(ip, nil)', 'safeReply(ip, nil)')
content = content.replace('reply(nil, NSError', 'safeReply(nil, NSError')
open('Sources/Vessel/XPCServer.swift', 'w').write(content)

# 3. BookmarkManager.swift
content = open('Sources/Vessel/BookmarkManager.swift').read()
content = re.sub(r'let runPanel = \{[\s\S]*?\n        \}\n\n        if #available\(macOS 14\.0, \*\) \{[\s\S]*?\} else \{[\s\S]*?DispatchQueue\.main\.sync \{[\s\S]*?runPanel\(\)[\s\S]*?\}[\s\S]*?\}', """        if Thread.isMainThread {
            let panel = NSOpenPanel()
            panel.message = "Vessel wymaga dostępu do katalogu: \\(path)"
            panel.prompt = "Przyznaj dostęp"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: path)
            
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.bookmarks[path] = bookmarkData
                    self.saveBookmarks()
                } catch {
                    userError = error
                }
            } else {
                userError = NSError(domain: "BookmarkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Użytkownik anulował przyznawanie uprawnień."])
            }
        } else {
            DispatchQueue.main.sync {
                let panel = NSOpenPanel()
                panel.message = "Vessel wymaga dostępu do katalogu: \\(path)"
                panel.prompt = "Przyznaj dostęp"
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = URL(fileURLWithPath: path)
                
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        self.bookmarks[path] = bookmarkData
                        self.saveBookmarks()
                    } catch {
                        userError = error
                    }
                } else {
                    userError = NSError(domain: "BookmarkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Użytkownik anulował przyznawanie uprawnień."])
                }
            }
        }""", content)
open('Sources/Vessel/BookmarkManager.swift', 'w').write(content)

# 4. ContainerViewModel.swift
content = open('Sources/Vessel/ContainerViewModel.swift').read()
content = content.replace('Task { await fetchContainers() }', 'Task { @MainActor in await self.fetchContainers() }')
# Replace `self.daemon.streamLogs(for: id)` and `self.currentLogs.append` to avoid Task closures
content = content.replace('let stream = self.daemon.streamLogs(for: id)', 'let d = self.daemon\n                        let stream = d.streamLogs(for: id)')
content = content.replace('let stream = try await self.daemon.startStatsStream(containerId: id)', 'let d = self.daemon\n                                    let stream = try await d.startStatsStream(containerId: id)')
open('Sources/Vessel/ContainerViewModel.swift', 'w').write(content)

print("Fixed data races")
