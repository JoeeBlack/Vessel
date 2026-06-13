import SwiftUI

struct MarketplaceView: View {
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 24)
    ]
    
    @State private var selectedFilter = "All"
    let filters = ["All", "Database", "Web", "Tooling"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Area
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Marketplace")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Discover and deploy verified container images.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Filters
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            Button(action: { selectedFilter = filter }) {
                                Text(filter)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedFilter == filter ? AppTheme.accentBlue : AppTheme.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == filter ? AppTheme.accentBlue.opacity(0.1) : AppTheme.cardBackground)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // Cards Grid
                LazyVGrid(columns: columns, spacing: 24) {
                    // Redis
                    marketplaceCard(
                        title: "Redis",
                        subtitle: "Official Image • Database",
                        description: "Redis is an open source (BSD licensed), in-memory data structure store, used as a database, cache, and message broker.",
                        downloads: "1B+",
                        stars: "12.4k",
                        icon: "cylinder.split.1x2",
                        iconColor: .red,
                        isPrimaryButton: true
                    )
                    
                    // PostgreSQL
                    marketplaceCard(
                        title: "PostgreSQL",
                        subtitle: "Official Image • Database",
                        description: "The World's Most Advanced Open Source Relational Database.",
                        downloads: "1B+",
                        stars: nil,
                        icon: "server.rack",
                        iconColor: AppTheme.accentBlue
                    )
                    
                    // NGINX
                    marketplaceCard(
                        title: "NGINX",
                        subtitle: "Official Image • Web",
                        description: "Official build of Nginx. Open source reverse proxy server.",
                        downloads: "1B+",
                        stars: nil,
                        icon: "globe",
                        iconColor: AppTheme.runningGreen
                    )
                    
                    // Node.js
                    marketplaceCard(
                        title: "Node.js",
                        subtitle: "Official Image • Tooling",
                        description: "Node.js is a JavaScript-based platform for server-side and networking applications.",
                        downloads: "1B+",
                        stars: nil,
                        icon: "n.circle.fill",
                        iconColor: .green
                    )
                    
                    // Python
                    marketplaceCard(
                        title: "Python",
                        subtitle: "Official Image • Tooling",
                        description: "Python is an interpreted, interactive, object-oriented, open-source programming language.",
                        downloads: "1B+",
                        stars: nil,
                        icon: "curlybraces",
                        iconColor: .blue
                    )
                }
            }
            .padding(40)
        }
    }
    
    private func marketplaceCard(title: String, subtitle: String, description: String, downloads: String, stars: String?, icon: String, iconColor: Color, isPrimaryButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                }
                
                Spacer()
                
                // Verified Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.runningGreen)
                        .frame(width: 6, height: 6)
                    Text("VERIFIED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.runningGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.runningGreen.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.top, 8)
            
            // Description
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary.opacity(0.8))
                .lineSpacing(4)
                .frame(minHeight: 60, alignment: .topLeading)
            
            Spacer()
            
            // Footer
            HStack {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text(downloads)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    
                    if let stars = stars {
                        HStack(spacing: 4) {
                            Image(systemName: "star")
                            Text(stars)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                if isPrimaryButton {
                    Button(action: {}) {
                        Text("Deploy")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentBlue)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                } else {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accentBlue)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(AppTheme.accentBlue, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Deploy Container")
                    .cursor(.pointingHand)
                }
            }
        }
        .padding(24)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 5)
        // Adding a subtle linear gradient to the first card to match mockup
        .background(
            isPrimaryButton ?
            LinearGradient(colors: [Color.white, Color(red: 240/255, green: 245/255, blue: 255/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : nil
        )
    }
}
