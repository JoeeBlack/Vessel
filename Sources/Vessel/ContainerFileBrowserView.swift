import SwiftUI
import UniformTypeIdentifiers

public struct ContainerFileBrowserView: View {
    let containerId: String
    @State private var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: FileItem.ID? = nil
    @State private var isTargeted = false

    public init(containerId: String, daemon: ContainerDaemon) {
        self.containerId = containerId
        _viewModel = State(initialValue: FileBrowserViewModel(containerId: containerId, daemon: daemon))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar / Breadcrumbs
            HStack {
                Button(action: {
                    navigateUp()
                }) {
                    Image(systemName: "arrow.up.doc.fill")
                }
                .disabled(viewModel.currentPath == "/")
                .help("Go up one level")
                .accessibilityLabel("Go up one level")

                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .accessibilityLabel("Refresh")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        let pathParts = viewModel.currentPath.split(separator: "/").map(String.init)

                        Button("/") {
                            Task { await viewModel.loadDirectory(path: "/") }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppTheme.accentBlue)

                        ForEach(Array(pathParts.enumerated()), id: \.offset) { index, part in
                            Text("/")
                                .foregroundColor(.gray)

                            Button(part) {
                                let newPath = "/" + pathParts[0...index].joined(separator: "/")
                                Task { await viewModel.loadDirectory(path: newPath) }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(index == pathParts.count - 1 ? AppTheme.textPrimary : AppTheme.accentBlue)
                        }
                    }
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            .background(AppTheme.cardBackground)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }

            Table(viewModel.files, selection: $selection) {
                TableColumn("Name") { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                            .foregroundColor(item.isDirectory ? AppTheme.accentBlue : .gray)
                        Text(item.name)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            Task { await viewModel.loadDirectory(path: item.path) }
                        }
                    }
                    .onDrag {
                        let provider = AsyncFilePromiseProvider(item: item, viewModel: viewModel)
                        return NSItemProvider(object: provider)
                    }
                }
                TableColumn("Size") { item in
                    Text(item.size)
                        .foregroundColor(AppTheme.textSecondary)
                }
                TableColumn("Date Modified") { item in
                    Text(item.modificationDate)
                        .foregroundColor(AppTheme.textSecondary)
                }
                TableColumn("Permissions") { item in
                    Text(item.permissions)
                        .foregroundColor(AppTheme.textSecondary)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { items in
                if let itemId = items.first, let item = viewModel.files.first(where: { $0.id == itemId }) {
                    if !item.isDirectory {
                        Button("Download...") {
                            downloadAction(for: item)
                        }
                    }
                }
            }
            // Drop support for upload
            .dropDestination(for: URL.self) { items, location in
                for url in items {
                    Task {
                        await viewModel.upload(from: url, to: url.lastPathComponent)
                    }
                }
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .overlay(
                Group {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.accentBlue, lineWidth: 3)
                            .background(Color.blue.opacity(0.1))
                            .allowsHitTesting(false)
                    }
                }
            )

            HStack {
                Button("Upload File...") {
                    uploadAction()
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(AppTheme.cardBackground)
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await viewModel.loadDirectory(path: "/")
        }
    }

    private func navigateUp() {
        var path = viewModel.currentPath
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        guard path != "/" && !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        Task { await viewModel.loadDirectory(path: parent) }
    }

    private func downloadAction(for item: FileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        panel.showsTagField = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.download(file: item, to: url)
                }
            }
        }
    }

    private func uploadAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.upload(from: url, to: url.lastPathComponent)
                }
            }
        }
    }

}
