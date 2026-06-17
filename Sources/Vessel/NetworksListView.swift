import SwiftUI

struct NetworksListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Area
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Networks")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)

                        Text("Manage container networks and DNS domains.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: {}) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Create Network")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentBlue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
                .padding(.bottom, 16)

                // Content
                VStack(spacing: 16) {
                    NetworkCardView(name: "vessel-default", driver: "bridge", subnet: "192.168.105.0/24", isSystem: true)
                }
            }
            .padding(40)
        }
    }
}

struct NetworkCardView: View {
    let name: String
    let driver: String
    let subnet: String
    let isSystem: Bool

    var body: some View {
        HStack {
            ZStack {
                Rectangle()
                    .fill(AppTheme.cardBackground)
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)

                Image(systemName: "network")
                    .foregroundColor(AppTheme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    if isSystem {
                        Text("SYSTEM")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentBlue.opacity(0.1))
                            .foregroundColor(AppTheme.accentBlue)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 12) {
                    Text("Driver: \(driver)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Subnet: \(subnet)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Spacer()

            if !isSystem {
                Button(action: {}) {
                    Image(systemName: "trash")
                        .foregroundColor(Color(red: 255/255, green: 100/255, blue: 100/255))
                        .padding(8)
                        .background(Material.ultraThin)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Delete network")
                .accessibilityLabel("Delete network")
            }
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
