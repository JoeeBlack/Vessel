import SwiftUI
import Containerization
import UniformTypeIdentifiers

struct ContentView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case containers = "Containers"
        case images = "Images"
        case settings = "Settings"
        
        var id: String { self.rawValue }
        var icon: String {
            switch self {
            case .containers: return "cube.box"
            case .images: return "square.stack.3d.up"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var viewModel = ContainerViewModel()
    @State private var selectedContainerId: String?
    @State private var selectedSidebarItem: SidebarItem? = .containers
    @State private var searchText: String = ""
    @State private var showingCreateContainer = false
    @State private var showError = false
    
    @State private var isFrameworkInstalled: Bool = {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel")
        let installedPath = dir.appendingPathComponent("installed").path
        let kernelPath = dir.appendingPathComponent("vmlinux").path
        return FileManager.default.fileExists(atPath: installedPath) && FileManager.default.fileExists(atPath: kernelPath)
    }()
    @State private var isInstalling = false
    @State private var installProgress: Double = 0.0
    @State private var installStatusMessage = ""

    var body: some View {
        ZStack {
            NavigationSplitView {
            sidebar
        } detail: {
            ZStack(alignment: .top) {
                AppTheme.mainBackgroundTop
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Navigation Bar
                    HStack {
                        if let selectedId = selectedContainerId, let workload = viewModel.workload(for: selectedId) {
                            // Breadcrumbs
                            HStack(spacing: 8) {
                                Text("Workloads")
                                    .foregroundColor(AppTheme.textSecondary)
                                    .onTapGesture {
                                        selectedContainerId = nil
                                    }
                                    .cursor(.pointingHand) // MacOS pointer
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text(workload.name)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: 14))
                            
                            Spacer()
                            

                        } else {
                            // Icons (search removed)
                            
                            Spacer()
                            
                            Button(action: {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.allowedContentTypes = [.yaml, .init(filenameExtension: "yml")!]
                                if panel.runModal() == .OK, let url = panel.url {
                                    Task {
                                        await viewModel.startPod(url: url)
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("Load Compose")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppTheme.cardBackground)
                                .foregroundColor(AppTheme.textPrimary)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.cardBorder, lineWidth: 1))
                                .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                    
                    Divider()
                        .background(AppTheme.cardBorder)
                    
                    // Main Content Area
                    if selectedSidebarItem == .containers {
                        if let selectedId = selectedContainerId, let workload = viewModel.workload(for: selectedId) {
                            // Detail View
                            if case .container(let container) = workload {
                                ContainerDetailView(container: container, viewModel: viewModel)
                            } else if case .pod(let pod) = workload {
                                VStack {
                                    Text("Pod Detail View for \(pod.name) not yet implemented")
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            // List View
                            let filteredWorkloads = searchText.isEmpty ? viewModel.workloads : viewModel.workloads.filter {
                                $0.name.localizedCaseInsensitiveContains(searchText)
                            }
                            ContainersListView(
                                workloads: filteredWorkloads,
                                loadingContainers: viewModel.loadingContainers,
                                viewModel: viewModel,
                                onSelect: { id in
                                    selectedContainerId = id
                                },
                                onStart: { id in
                                    Task { await viewModel.startContainer(id: id) }
                                },
                                onStop: { id in
                                    Task { await viewModel.stopContainer(id: id) }
                                },
                                onDelete: { id in
                                    Task { await viewModel.deleteContainer(id: id) }
                                },
                                onNewContainer: {
                                    showingCreateContainer = true
                                }
                            )
                        }
                    } else if selectedSidebarItem == .images {
                        ImagesListView()
                    } else if selectedSidebarItem == .settings {
                        SettingsView()
                    } else {
                        // Empty state for other tabs
                        VStack {
                            Spacer()
                            Text("\(selectedSidebarItem?.rawValue ?? "")")
                                .font(.largeTitle)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                    }
                }
            }
            }
            
            // Installation Overlay
            if !isFrameworkInstalled {
                installOverlay
            }
        }
        .sheet(isPresented: $showingCreateContainer) {
            CreateContainerView { name, image, rootfs, rosetta, networking, cpus, memoryGB, envVars, volumes in
                let vesselVolumes = volumes.map { VesselVolume(host: $0.host, container: $0.container) }
                Task {
                    await viewModel.createContainer(name: name, image: image, rootfsSizeGB: rootfs, rosetta: rosetta, networking: networking, cpus: cpus, memoryGB: memoryGB, envVars: envVars, volumes: vesselVolumes)
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil {
                showError = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onAppear {
            // Already checked in initialization
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        // Sidebar Customization
        VStack(alignment: .leading, spacing: 0) {
            // Header (Vessel Logo)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBlue)
                        .frame(width: 40, height: 40)
                    Image(systemName: "cube.transparent")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vessel")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.accentBlue)
                    Text("Infrastructure Engine")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            
            Divider()
                .background(AppTheme.cardBorder)
            
            // Menu Items
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(SidebarItem.allCases) { item in
                        Button(action: {
                            selectedSidebarItem = item
                            selectedContainerId = nil // reset selection
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedSidebarItem == item ? AppTheme.accentBlue : AppTheme.textPrimary)
                                    .frame(width: 24)
                                
                                Text(item.rawValue)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(selectedSidebarItem == item ? AppTheme.accentBlue : AppTheme.textPrimary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSidebarItem == item ? AppTheme.accentBlue.opacity(0.05) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 24)
            }
            Spacer()
        }
        .background(AppTheme.sidebarBackground)
        .navigationSplitViewColumnWidth(260)
    }
    
    private var installOverlay: some View {
        ZStack {
            AppTheme.mainBackgroundTop.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.accentBlue)
                
                Text("Container Framework Required")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Vessel requires the native containerization environment to run workloads.")
                    .foregroundColor(AppTheme.textSecondary)
                
                if isInstalling {
                    ProgressView(value: installProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                        .tint(AppTheme.accentBlue)
                    
                    Text("\(Int(installProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Text(installStatusMessage)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.top, 4)
                } else {
                    Button(action: startInstallation) {
                        Text("Install Framework")
                            .fontWeight(.medium)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(AppTheme.accentBlue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
        }
    }
    
    private func startInstallation() {
        guard !isInstalling else { return }
        isInstalling = true
        Task.detached {
            do {
                let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".vessel")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                
                let kernelPath = dir.appendingPathComponent("vmlinux")
                if !FileManager.default.fileExists(atPath: kernelPath.path) {
                    await MainActor.run { 
                        installProgress = 0.1 
                        installStatusMessage = "Starting download..."
                    }
                    let urlStr = "https://github.com/kata-containers/kata-containers/releases/download/3.17.0/kata-static-3.17.0-arm64.tar.xz"
                    let tarPath = dir.appendingPathComponent("kata.tar.xz")
                    
                    let downloader = KernelDownloader()
                    downloader.onProgress = { pct, written, expected in
                        Task { @MainActor in
                            installProgress = 0.1 + (pct * 0.4)
                            installStatusMessage = String(format: "Downloading Linux Kernel: %.1f MB / %.1f MB", written, expected)
                        }
                    }
                    
                    let downloadedURL = try await downloader.download(url: URL(string: urlStr)!)
                    if FileManager.default.fileExists(atPath: tarPath.path) {
                        try FileManager.default.removeItem(at: tarPath)
                    }
                    try FileManager.default.moveItem(at: downloadedURL, to: tarPath)
                    
                    await MainActor.run { 
                        installProgress = 0.5 
                        installStatusMessage = "Extracting Kernel files..."
                    }
                    
                    let extract = Process()
                    extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    extract.arguments = ["-xf", tarPath.path, "-C", dir.path, "--strip-components=1"]
                    try extract.run()
                    extract.waitUntilExit()
                    
                    await MainActor.run { 
                        installProgress = 0.8 
                        installStatusMessage = "Cleaning up..."
                    }
                    
                    let extractedKernelSymlink = dir.appendingPathComponent("opt/kata/share/kata-containers/vmlinux.container")
                    if let destPath = try? FileManager.default.destinationOfSymbolicLink(atPath: extractedKernelSymlink.path) {
                        let actualKernel = extractedKernelSymlink.deletingLastPathComponent().appendingPathComponent(destPath)
                        try? FileManager.default.removeItem(at: kernelPath)
                        if FileManager.default.fileExists(atPath: actualKernel.path) {
                            try FileManager.default.copyItem(at: actualKernel, to: kernelPath)
                        }
                    } else {
                        if FileManager.default.fileExists(atPath: extractedKernelSymlink.path) {
                            try? FileManager.default.removeItem(at: kernelPath)
                            try FileManager.default.copyItem(at: extractedKernelSymlink, to: kernelPath)
                        }
                    }
                    
                    await MainActor.run { 
                        installProgress = 0.9 
                        installStatusMessage = "Downloading initfs (Apple Containerization)..."
                    }
                    
                    let kernel = Kernel(path: kernelPath, platform: .linuxArm)
                    _ = try await ContainerManager(
                        kernel: kernel,
                        initfsReference: "ghcr.io/apple/containerization/vminit:0.33.4",
                        network: nil,
                        rosetta: true
                    )
                    
                    // Cleanup
                    try? FileManager.default.removeItem(at: tarPath)
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("opt"))
                }
                
                FileManager.default.createFile(atPath: dir.appendingPathComponent("installed").path, contents: Data())
                
                await MainActor.run {
                    installProgress = 1.0
                    isFrameworkInstalled = true
                    isInstalling = false
                }
            } catch {
                print("Installation failed: \(error)")
                await MainActor.run {
                    isInstalling = false
                }
            }
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                cursor.pop()
            }
        }
    }
}

class KernelDownloader: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Double, Double, Double) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?
    
    func download(url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let writtenMB = Double(totalBytesWritten) / 1048576.0
        let expectedMB = Double(totalBytesExpectedToWrite) / 1048576.0
        onProgress?(pct, writtenMB, expectedMB)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tempURL)
        continuation?.resume(returning: tempURL)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
        }
    }
}
