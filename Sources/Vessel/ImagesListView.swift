import SwiftUI
import VesselXPC

@Observable
class ImagesViewModel: @unchecked Sendable {
    var images: [VesselImage] = []
    var pullQuery: String = ""
    var isPulling: Bool = false
    var pullProgress: Double = 0.0
    var pullTask: Task<Void, Never>? = nil

    private let daemon = ContainerDaemon()
    
    func fetchImages() async {
        do {
            let fetched = try await daemon.fetchImages()
            await MainActor.run {
                self.images = fetched
            }
        } catch {
            print("Failed to fetch images: \(error)")
        }
    }

    private func normalize(reference: String) -> String {
        var ref = reference
        let parts = ref.split(separator: "/")
        if parts.isEmpty { return ref }

        let firstPart = String(parts[0])
        if !firstPart.contains(".") && firstPart != "localhost" {
            if parts.count == 1 {
                ref = "docker.io/library/\(ref)"
            } else {
                ref = "docker.io/\(ref)"
            }
        }

        if !ref.contains(":") {
            ref += ":latest"
        }

        return ref
    }

    func pullImage() {
        guard !self.pullQuery.isEmpty else { return }
        self.isPulling = true
        self.pullProgress = 0.0

        let query = normalize(reference: pullQuery)
        pullTask = Task {
            do {
                try await daemon.pullImage(reference: query) { pct in
                    Task { @MainActor in
                        self.pullProgress = pct
                    }
                }
                if !Task.isCancelled {
                    await self.fetchImages()
                }
            } catch {
                if !Task.isCancelled {
                    print("Failed to pull: \(error)")
                }
            }
            if !Task.isCancelled {
                await MainActor.run {
                    self.isPulling = false
                    self.pullQuery = ""
                    self.pullProgress = 0.0
                }
            }
        }
    }

    func deleteImage(_ image: VesselImage) {
        let rawRef = "\(image.repository):\(image.tag)"
        let ref = normalize(reference: rawRef)
        Task {
            do {
                try await daemon.deleteImage(reference: ref)
                await self.fetchImages()
            } catch {
                print("Failed to delete image: \(error)")
            }
        }
    }
}

struct ImagesListView: View {
    @State private var viewModel = ImagesViewModel()

    let popularImages = ["ubuntu:latest", "alpine:latest", "nginx:latest", "redis:latest", "node:latest"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header Area
            VStack(alignment: .leading, spacing: 8) {
                Text("OCI Images")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Manage container images from remote registries. Search Docker Hub directly.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            
            // Pull / Search Area
            HStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textSecondary)
                    TextField("Search Docker Hub or pull e.g. ubuntu:latest", text: Bindable(viewModel).pullQuery)
                        .textFieldStyle(.plain)
                        .foregroundColor(AppTheme.textPrimary)
                        .disabled(viewModel.isPulling)
                        .onChange(of: viewModel.pullQuery) { _, newValue in
                            if !newValue.contains(":") && !newValue.isEmpty {
                                // Realistically here we would trigger a docker hub search API
                                // For now, we simulate finding the image on Docker Hub and allow pulling.
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Material.ultraThin)
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
                
                Button(action: viewModel.pullImage) {
                    Text(viewModel.isPulling ? "Pulling..." : "Pull Image")
                        .fontWeight(.medium)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(viewModel.isPulling ? AppTheme.stoppedRed : AppTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPulling || viewModel.pullQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 32)
            
            // Popular Suggestions
            if !viewModel.isPulling {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Popular:")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.trailing, 4)
                        
                        ForEach(popularImages, id: \.self) { img in
                            Button(action: {
                                viewModel.pullQuery = img
                                viewModel.pullImage()
                            }) {
                                Text(img)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Material.ultraThin)
                                    .background(AppTheme.cardBackground)
                                    .foregroundColor(AppTheme.accentBlue)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }
            
            // Image List
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.isPulling {
                        PullingImageCardView(query: viewModel.pullQuery, progress: viewModel.pullProgress) {
                            viewModel.pullTask?.cancel()
                            viewModel.isPulling = false
                            viewModel.pullProgress = 0.0
                        }
                    }
                    
                    if viewModel.images.isEmpty {
                        Text("No images downloaded.")
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(viewModel.images) { img in
                            ImageCardView(
                                image: img,
                                onDelete: { viewModel.deleteImage(img) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .task {
            await viewModel.fetchImages()
        }
    }
}

struct ImageCardView: View {
    let image: VesselImage
    let onDelete: () -> Void

    var body: some View {
        HStack {
            ZStack {
                Rectangle()
                    .fill(AppTheme.cardBackground)
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
                
                Image(systemName: "square.stack.3d.up")
                    .foregroundColor(AppTheme.accentBlue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(image.repository)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(image.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(image.tag)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.cardBorder)
                    .foregroundColor(AppTheme.textPrimary)
                    .cornerRadius(6)
                
                Text(image.size)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(Color(red: 255/255, green: 100/255, blue: 100/255))
                    .padding(8)
                    .background(Material.ultraThin)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Delete image")
            .accessibilityLabel("Delete image")
            .padding(.leading, 12)
        }
        .padding(16)
        .background(Material.ultraThin)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

struct PullingImageCardView: View {
    let query: String
    let progress: Double
    let onCancel: () -> Void
    
    @State private var isAnimatingOverlay = false
    
    var body: some View {
        HStack {
            ZStack {
                Rectangle()
                    .fill(AppTheme.cardBackground)
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
                
                Image(systemName: "square.stack.3d.down.right")
                    .foregroundColor(AppTheme.accentBlue)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(query)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.accentBlue)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.cardBorder)
                            .frame(height: 10)
                        
                        Capsule()
                            .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 90/255, green: 200/255, blue: 250/255), AppTheme.accentBlue]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geometry.size.width * CGFloat(progress), 0), height: 10)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)
                            .shadow(color: AppTheme.accentBlue.opacity(0.5), radius: 6, x: 0, y: 2)
                    }
                }
                .frame(height: 10)
            }
            .padding(.leading, 8)
            
            Spacer()
            
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .foregroundColor(Color(red: 255/255, green: 100/255, blue: 100/255))
                    .padding(8)
                    .background(Material.ultraThin)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Cancel pull")
            .accessibilityLabel("Cancel pull")
            .padding(.leading, 12)
        }
        .padding(16)
        .background(
            ZStack {
                AppTheme.mainBackgroundTop
                GeometryReader { geometry in
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.clear, AppTheme.accentBlue.opacity(0.08), Color.clear]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width)
                        .offset(x: isAnimatingOverlay ? geometry.size.width : -geometry.size.width)
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                isAnimatingOverlay = true
                            }
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        )
        .compositingGroup()
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}
