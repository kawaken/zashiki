import AppKit
import Darwin
import Foundation

struct SurfaceAgentStatus: Identifiable {
    let id: UUID
    let surface: Zashiki.SurfaceView
    let provider: AgentProvider
    let activity: AgentActivity
    let directory: String?
    let lastUpdatedAt: Date

    var helpText: String {
        let location = directory ?? "Unknown working directory"
        return provider.displayName + "\nStatus: " + activity.displayName + "\nPath: " + location
    }
}

/// Tracks agent detection for the Surfaces currently shown in one terminal
/// window. The view owns the polling lifetime, so hidden panes do not keep
/// reading terminal buffers.
@MainActor
final class AgentStatusModel: ObservableObject {
    @Published private(set) var agents: [SurfaceAgentStatus] = []

    private var history: [UUID: AgentHistory] = [:]

    func refresh(surfaces: [Zashiki.SurfaceView], now: Date = Date()) {
        var next: [SurfaceAgentStatus] = []
        var activeIDs: Set<UUID> = []

        for surface in surfaces {
            guard let foregroundPID = surface.surfaceModel?.foregroundPID,
                  let processName = ProcessNameResolver.name(for: foregroundPID)
            else { continue }

            let screenContents = surface.cachedVisibleContents.get()
            let inputLine = surface.cachedInputLineBeforeCursor.get()
            let previous = history[surface.id]
            let detection = AgentDetector.detect(.init(
                processName: processName,
                screenContents: screenContents,
                inputLine: inputLine))

            guard let detection else { continue }
            activeIDs.insert(surface.id)

            let lastUpdatedAt: Date
            if let previous,
               previous.detection == detection,
               previous.screenContents == screenContents {
                lastUpdatedAt = previous.lastUpdatedAt
            } else {
                lastUpdatedAt = now
            }

            history[surface.id] = AgentHistory(
                detection: detection,
                screenContents: screenContents,
                lastUpdatedAt: lastUpdatedAt)
            next.append(.init(
                id: surface.id,
                surface: surface,
                provider: detection.provider,
                activity: detection.activity,
                directory: surface.pwd,
                lastUpdatedAt: lastUpdatedAt))
        }

        history = history.filter { activeIDs.contains($0.key) }
        agents = next.sorted { lhs, rhs in
            lhs.provider.displayName.localizedStandardCompare(rhs.provider.displayName) == .orderedAscending
        }
    }

    func clear() {
        history.removeAll()
        agents = []
    }
}

private struct AgentHistory {
    let detection: AgentDetection
    let screenContents: String
    let lastUpdatedAt: Date
}

private enum ProcessNameResolver {
    static func name(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
