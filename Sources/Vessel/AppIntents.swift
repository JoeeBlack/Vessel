import AppIntents
import Foundation

// MARK: - AppEntity
public struct ContainerEntity: AppEntity {
    public var id: String

    @Property(title: "Name")
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Container"

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static let defaultQuery = ContainerEntityQuery()
}

// MARK: - EntityQuery
public struct ContainerEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ContainerEntity] {
        let daemon = ContainerDaemon()
        // We use fetchActiveWorkloads to include both stopped and running containers and pods,
        // allowing users to start stopped workloads via Spotlight/Shortcuts.
        let workloads = try await daemon.fetchActiveWorkloads()
        return workloads
            .filter { identifiers.contains($0.id) }
            .map { ContainerEntity(id: $0.id, name: $0.name) }
    }

    public func suggestedEntities() async throws -> [ContainerEntity] {
        let daemon = ContainerDaemon()
        let workloads = try await daemon.fetchActiveWorkloads()
        return workloads.map { ContainerEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Intents
public struct StartContainerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Container"
    public static let description = IntentDescription("Starts a specific Vessel container.")

    @Parameter(title: "Container")
    public var container: ContainerEntity

    public init() {}

    public func perform() async throws -> some IntentResult {
        let daemon = ContainerDaemon()
        try await daemon.start(containerId: container.id)
        return .result()
    }
}

public struct StopContainerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Container"
    public static let description = IntentDescription("Stops a specific Vessel container.")

    @Parameter(title: "Container")
    public var container: ContainerEntity

    public init() {}

    public func perform() async throws -> some IntentResult {
        let daemon = ContainerDaemon()
        try await daemon.stop(containerId: container.id, force: false)
        return .result()
    }
}

// MARK: - AppShortcutsProvider
public struct VesselShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartContainerIntent(),
            phrases: [
                "Start \(\.$container) in \(.applicationName)",
                "Run \(\.$container) in \(.applicationName)"
            ],
            shortTitle: "Start Container",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: StopContainerIntent(),
            phrases: [
                "Stop \(\.$container) in \(.applicationName)",
                "Halt \(\.$container) in \(.applicationName)"
            ],
            shortTitle: "Stop Container",
            systemImageName: "stop.fill"
        )
    }
}
