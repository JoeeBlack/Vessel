import Foundation
import SwiftUI
import Observation

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let isDirectory: Bool
    public let size: String
    public let modificationDate: String
    public let permissions: String
    public let path: String // Full absolute path
}

@Observable
public final class FileBrowserViewModel: @unchecked Sendable {
    public var currentPath: String = "/"
    public var files: [FileItem] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    // Memory cache for paths
    private var pathCache: [String: [FileItem]] = [:]

    private let daemon: ContainerDaemon
    private let containerId: String

    public init(containerId: String, daemon: ContainerDaemon) {
        self.containerId = containerId
        self.daemon = daemon
    }

    @MainActor
    public func loadDirectory(path: String) async {
        self.isLoading = true
        self.errorMessage = nil
        self.currentPath = path

        if let cached = pathCache[path] {
            self.files = cached
            self.isLoading = false
            return
        }

        do {
            let output = try await daemon.listFiles(in: path, containerId: containerId)
            let items = parseLSOutput(output: output, parentPath: path)
            self.files = items
            self.pathCache[path] = items
        } catch {
            self.errorMessage = "Failed to load directory: \(error.localizedDescription)"
        }

        self.isLoading = false
    }

    @MainActor
    public func refresh() async {
        pathCache.removeValue(forKey: currentPath)
        await loadDirectory(path: currentPath)
    }

    private func parseLSOutput(output: String, parentPath: String) -> [FileItem] {
        var items: [FileItem] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.isEmpty || line.hasPrefix("total ") {
                continue
            }

            // Example:
            // drwxr-xr-x    2 root     root          4096 Oct 27 10:00 bin/
            // -rw-r--r--    1 root     root            12 Oct 27 10:00 file.txt

            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            if parts.count >= 9 {
                let permissions = String(parts[0])
                let size = String(parts[4])
                let month = String(parts[5])
                let day = String(parts[6])
                let time = String(parts[7])
                let dateStr = "\(month) \(day) \(time)"

                var name = String(parts[8])

                // ls -p appends / to directories
                let isDirectory = name.hasSuffix("/") || permissions.hasPrefix("d")
                if name.hasSuffix("/") {
                    name = String(name.dropLast())
                }

                // Handle symlinks (name -> target)
                if let arrowIndex = name.range(of: " -> ") {
                    name = String(name[..<arrowIndex.lowerBound])
                }

                // Skip . and ..
                if name == "." || name == ".." {
                    continue
                }

                let fullPath = (parentPath.hasSuffix("/") ? parentPath : parentPath + "/") + name

                items.append(FileItem(
                    name: name,
                    isDirectory: isDirectory,
                    size: isDirectory ? "--" : formatSize(size),
                    modificationDate: dateStr,
                    permissions: permissions,
                    path: fullPath
                ))
            }
        }

        // Sort: directories first, then alphabetically
        return items.sorted {
            if $0.isDirectory && !$1.isDirectory { return true }
            if !$0.isDirectory && $1.isDirectory { return false }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    private func formatSize(_ sizeStr: String) -> String {
        guard let bytes = Int64(sizeStr) else { return sizeStr }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @MainActor
    public func download(file: FileItem, to destination: URL) async {
        do {
            try await daemon.downloadFile(containerId: containerId, path: file.path, to: destination)
        } catch {
            self.errorMessage = "Failed to download \(file.name): \(error.localizedDescription)"
        }
    }

    @MainActor
    public func upload(from source: URL, to destinationName: String) async {
        do {
            let destPath = (currentPath.hasSuffix("/") ? currentPath : currentPath + "/") + destinationName
            try await daemon.uploadFile(containerId: containerId, from: source, to: destPath)
            await refresh()
        } catch {
            self.errorMessage = "Failed to upload \(destinationName): \(error.localizedDescription)"
        }
    }
}
