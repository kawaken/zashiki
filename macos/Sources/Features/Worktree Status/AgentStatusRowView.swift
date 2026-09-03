import SwiftUI

struct AgentStatusRowView: View {
    let agent: SurfaceAgentStatus
    let onFocus: () -> Void

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: 8) {
                Image(systemName: providerSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.provider.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Image(systemName: activitySymbol)
                            .foregroundStyle(activityColor)

                        Text(agent.activity.displayName)
                            .font(.caption)
                            .foregroundStyle(activityColor)
                    }

                    Text(agent.directory ?? "Unknown working directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Updated ") + Text(agent.lastUpdatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help(agent.helpText)
        .accessibilityLabel(agent.helpText.replacingOccurrences(of: "\n", with: ", "))
    }

    private var providerSymbol: String {
        switch agent.provider {
        case .claude: return "brain.head.profile"
        case .codex: return "terminal"
        }
    }

    private var activitySymbol: String {
        switch agent.activity {
        case .working: return "circle.fill"
        case .waiting: return "exclamationmark.bubble.fill"
        case .idle: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private var activityColor: Color {
        switch agent.activity {
        case .working: return .green
        case .waiting: return .orange
        case .idle: return .blue
        case .unknown: return .secondary
        }
    }
}
