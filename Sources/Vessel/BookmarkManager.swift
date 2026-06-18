import Foundation
import AppKit

public class BookmarkManager: @unchecked Sendable {
    public static let shared = BookmarkManager()

    private let userDefaultsKey = "VesselSecurityScopedBookmarks"
    private var activeUrls: [URL] = []
    private let activeUrlsLock = NSLock()

    private init() {
        restoreAccess()
    }

    public func resolveAndAccess(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let resolvedPath = URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath().path
        let url = URL(fileURLWithPath: resolvedPath)

        // If we already have a valid bookmark that gives access, return
        if hasAccess(to: url) {
            return
        }

        // Prompt the user for access
        try requestAccessOnMainThread(for: url)
    }

    private func hasAccess(to url: URL) -> Bool {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] else {
            return false
        }

        // Check if there is an exact match or if a parent directory is bookmarked
        var currentURL = url
        var isStale = false

        while true {
            if let bookmarkData = bookmarks[currentURL.path],
               let resolvedUrl = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {

                if isStale {
                    // Update bookmark if it's stale
                    try? saveBookmark(for: resolvedUrl)
                }

                // If it's already in activeUrls, we don't need to start accessing it again to avoid leaks
                activeUrlsLock.lock()
                let contains = activeUrls.contains(resolvedUrl)
                activeUrlsLock.unlock()
                if contains {
                    return true
                }

                if resolvedUrl.startAccessingSecurityScopedResource() {
                    activeUrlsLock.lock()
                    activeUrls.append(resolvedUrl)
                    activeUrlsLock.unlock()
                    return true
                }
            }
            if currentURL.path == "/" { break }
            currentURL = currentURL.deletingLastPathComponent()
        }
        return false
    }

    private func requestAccessOnMainThread(for url: URL) throws {
        let panelAction: @MainActor () -> Error? = {
            let panel = NSOpenPanel()
            panel.message = "Vessel needs access to the folder '\(url.path)' to mount it into the container."
            panel.prompt = "Grant Access"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = url

            if panel.runModal() == .OK, let selectedUrl = panel.url {
                if selectedUrl.path == url.path || url.path.hasPrefix(selectedUrl.path + "/") {
                    do {
                        try self.saveBookmark(for: selectedUrl)
                        if selectedUrl.startAccessingSecurityScopedResource() {
                            self.activeUrlsLock.lock()
                            self.activeUrls.append(selectedUrl)
                            self.activeUrlsLock.unlock()
                            return nil
                        } else {
                            return NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped resource."])
                        }
                    } catch {
                        return error
                    }
                } else {
                    return NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "User selected a different directory. Access denied."])
                }
            } else {
                return NSError(domain: "Vessel", code: 403, userInfo: [NSLocalizedDescriptionKey: "User denied access to the requested path."])
            }
        }

        var userError: Error?
        if Thread.isMainThread {
            userError = MainActor.assumeIsolated {
                panelAction()
            }
        } else {
            userError = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    panelAction()
                }
            }
        }

        if let error = userError {
            throw error
        }
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

        var bookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] ?? [:]
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: userDefaultsKey)
    }

    public func restoreAccess() {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Data] else {
            return
        }

        var updatedBookmarks = bookmarks
        var isStale = false

        for (path, bookmarkData) in bookmarks {
            if let resolvedUrl = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    if let newData = try? resolvedUrl.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        updatedBookmarks[path] = newData
                    }
                }
                if resolvedUrl.startAccessingSecurityScopedResource() {
                    activeUrlsLock.lock()
                    activeUrls.append(resolvedUrl)
                    activeUrlsLock.unlock()
                }
            }
        }

        UserDefaults.standard.set(updatedBookmarks, forKey: userDefaultsKey)
    }

    deinit {
        activeUrlsLock.lock()
        for url in activeUrls {
            url.stopAccessingSecurityScopedResource()
        }
        activeUrlsLock.unlock()
    }
}
