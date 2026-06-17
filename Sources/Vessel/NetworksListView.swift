import SwiftUI

struct NetworksListView: View {
    @Environment(ContainerViewModel.self) private var viewModel
    @State private var showingAddRule = false
    @State private var newRuleSource: VesselDomain = .work
    @State private var newRuleTarget: VesselDomain = .personal
    @State private var newRuleIsAllowed: Bool = false

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

                Divider().padding(.vertical, 16)

                // Domain Isolation Rules
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Domain Isolation Rules")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)

                        Text("Configure network access between Qubes OS style domains.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: { showingAddRule = true }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Rule")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.cardBorder)
                        .foregroundColor(AppTheme.textPrimary)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
                .padding(.bottom, 16)

                VStack(spacing: 16) {
                    ForEach(viewModel.domainRules) { rule in
                        DomainRuleCardView(rule: rule) {
                            viewModel.removeDomainRule(id: rule.id)
                        }
                    }
                    if viewModel.domainRules.isEmpty {
                        Text("No domain isolation rules configured.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.vertical, 24)
                    }
                }
            }
            .padding(40)
        }
        .sheet(isPresented: $showingAddRule) {
            addRuleSheet
        }
    }

    private var addRuleSheet: some View {
        VStack(spacing: 24) {
            Text("Add Domain Rule")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Source Domain:")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $newRuleSource) {
                        ForEach(VesselDomain.allCases, id: \.self) { domain in
                            Text(domain.rawValue.capitalized).tag(domain)
                        }
                    }
                }

                HStack {
                    Text("Target Domain:")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $newRuleTarget) {
                        ForEach(VesselDomain.allCases, id: \.self) { domain in
                            Text(domain.rawValue.capitalized).tag(domain)
                        }
                    }
                }

                Toggle("Allow Connection", isOn: $newRuleIsAllowed)
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    showingAddRule = false
                }

                Button("Add") {
                    viewModel.addDomainRule(source: newRuleSource, target: newRuleTarget, isAllowed: newRuleIsAllowed)
                    showingAddRule = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}

struct DomainRuleCardView: View {
    let rule: DomainRule
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // Source Domain
            domainBadge(domain: rule.source)

            // Arrow/Action
            VStack(spacing: 4) {
                Image(systemName: rule.isAllowed ? "arrow.right" : "xmark")
                    .foregroundColor(rule.isAllowed ? AppTheme.runningGreen : AppTheme.stoppedRed)
                    .font(.system(size: 14, weight: .bold))

                Text(rule.isAllowed ? "ALLOW" : "DENY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(rule.isAllowed ? AppTheme.runningGreen : AppTheme.stoppedRed)
            }
            .padding(.horizontal, 16)

            // Target Domain
            domainBadge(domain: rule.target)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(AppTheme.stoppedRed)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Delete rule")
            .accessibilityLabel("Delete rule")
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rule.isAllowed ? AppTheme.runningGreen.opacity(0.3) : AppTheme.stoppedRed.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func domainBadge(domain: VesselDomain) -> some View {
        HStack {
            Circle()
                .fill(AppTheme.color(for: domain))
                .frame(width: 8, height: 8)
            Text(domain.rawValue.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.color(for: domain).opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.color(for: domain).opacity(0.5), lineWidth: 1)
        )
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
                        .background(AppTheme.cardBackground)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Delete network")
                .accessibilityLabel("Delete network")
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}
