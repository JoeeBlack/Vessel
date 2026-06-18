import SwiftUI
import Foundation

struct VolumesManagerView: View {
    @ObservedObject var viewModel: ContainerViewModel

    @State private var selectedVolume: VesselVolume?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedVolume) {
                ForEach(viewModel.workloads, id: \VesselWorkload.id) { workload in
                    let volumes = getVolumes(for: workload)
                    if !volumes.isEmpty {
                        Section(header: Text(workload.name)) {
                            ForEach(volumes, id: \.self) { volume in
                                NavigationLink(value: volume) {
                                    HStack {
                                        Image(systemName: "externaldrive.fill")
                                            .foregroundColor(AppTheme.accentBlue)
                                        Text(volume.container)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Volumes")
        } detail: {
            if let volume = selectedVolume {
                VolumeExplorerView(volume: volume)
            } else {
                VStack {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 64))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Select a volume to explore")
                        .font(.title2)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }

    private func getVolumes(for workload: VesselWorkload) -> [VesselVolume] {
        switch workload {
        case .container(let container):
            return container.volumes
        case .pod(let pod):
            return pod.containers.flatMap { $0.volumes }
        }
    }
}

struct VolumeExplorerView: View {
    let volume: VesselVolume

    @State private var currentPath: URL
    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var fileContent: String = ""
    @State private var isEditing: Bool = false
    @State private var errorMessage: String?
    @State private var isSystemLoadingContent: Bool = false

    init(volume: VesselVolume) {
        self.volume = volume
        let url = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath()
        _currentPath = State(initialValue: url)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Path Navigation
            HStack {
                Button(action: goUp) {
                    Image(systemName: "arrow.up")
                }
                .disabled(currentPath.path == URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path)

                Text(currentPath.path)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button(action: loadFiles) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()
            .background(AppTheme.cardBackground)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }

            HStack(spacing: 0) {
                // File List
                List(files, id: \.self, selection: $selectedFile) { file in
                    let isDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    HStack {
                        Image(systemName: isDir ? "folder.fill" : "doc.fill")
                            .foregroundColor(isDir ? .blue : .primary)
                        Text(file.lastPathComponent)
                    }
                    .onTapGesture(count: 2) {
                        if isDir {
                            currentPath = file
                            loadFiles()
                        }
                    }
                }
                .onChange(of: selectedFile) { newSelection in
                    if let file = newSelection {
                        let isDir = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        if !isDir {
                            loadFileContent(url: file)
                        }
                    }
                }
                .frame(width: 300)

                Divider()

                // File Editor
                VStack {
                    if let selectedFile = selectedFile, ((try? selectedFile.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false) {
                        HStack {
                            Text(selectedFile.lastPathComponent)
                                .font(.headline)
                            Spacer()
                            Button(action: saveFile) {
                                Text("Save")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isEditing)
                        }
                        .padding()

                        TextEditor(text: $fileContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .onChange(of: fileContent) { _ in
                                if !isSystemLoadingContent {
                                    isEditing = true
                                }
                            }
                    } else {
                        Text("Select a file to view or edit")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadFiles)
        .onChange(of: volume) { newVolume in
            currentPath = URL(fileURLWithPath: newVolume.host).resolvingSymlinksInPath()
            selectedFile = nil
            fileContent = ""
            isEditing = false
            errorMessage = nil
            loadFiles()
        }
    }

    // The containerization framework (Sentinel) already ensures valid host paths.
    // So we don't need to block /var or /private anymore.

    private func loadFiles() {
        errorMessage = nil
        let fm = FileManager.default
        do {
            let rootPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
            let resolvedCurrentPath = currentPath.resolvingSymlinksInPath().path

            // Security check: ensure we are within the volume host path
            // Use hasPrefix with a trailing slash to prevent directory traversal to identically prefixed sibling directories.
            let rootPathWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            let resolvedCurrentPathWithSlash = resolvedCurrentPath.hasSuffix("/") ? resolvedCurrentPath : resolvedCurrentPath + "/"

            // Allow exact match of rootPath, or children
            let isSafe = resolvedCurrentPath == rootPath || resolvedCurrentPathWithSlash.hasPrefix(rootPathWithSlash)
            if !isSafe {
                errorMessage = "Security Error: Path traversal detected."
                files = []
                return
            }

            let contents = try fm.contentsOfDirectory(at: currentPath, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            files = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            errorMessage = "Failed to load directory: \(error.localizedDescription)"
            files = []
        }
    }

    private func goUp() {
        let parent = currentPath.deletingLastPathComponent()
        let rootPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
        let resolvedParent = parent.resolvingSymlinksInPath().path
        let rootPathWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedParentWithSlash = resolvedParent.hasSuffix("/") ? resolvedParent : resolvedParent + "/"
        let isSafe = resolvedParent == rootPath || resolvedParentWithSlash.hasPrefix(rootPathWithSlash)
        if isSafe {
            currentPath = parent
            loadFiles()
        }
    }

    private func loadFileContent(url: URL) {
        isSystemLoadingContent = true
        defer {
            DispatchQueue.main.async {
                isSystemLoadingContent = false
            }
        }
        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            fileContent = ""
        }
    }

    private func saveFile() {
        guard let selectedFile = selectedFile else { return }

        let resolvedPath = selectedFile.resolvingSymlinksInPath().path
        let rootPath = URL(fileURLWithPath: volume.host).resolvingSymlinksInPath().path
        let rootPathWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let resolvedPathWithSlash = resolvedPath.hasSuffix("/") ? resolvedPath : resolvedPath + "/"
        let isSafe = resolvedPath == rootPath || resolvedPathWithSlash.hasPrefix(rootPathWithSlash)

        if !isSafe {
             errorMessage = "Security Error: Path traversal detected on save."
             return
        }

        do {
            let data = fileContent.data(using: .utf8)!
            let fm = FileManager.default
            let oldAttributes = try? fm.attributesOfItem(atPath: selectedFile.path)
            try data.write(to: selectedFile, options: [.atomic])
            if let oldPerms = oldAttributes?[.posixPermissions] {
                try fm.setAttributes([.posixPermissions: oldPerms], ofItemAtPath: selectedFile.path)
            }
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }
}
