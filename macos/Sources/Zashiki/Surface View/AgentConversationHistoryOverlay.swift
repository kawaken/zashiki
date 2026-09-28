import SwiftUI

struct AgentConversationHistoryOverlay: View {
    let surfaceView: Zashiki.SurfaceView

    @ObservedObject var history: AgentConversationHistory
    @State private var hoveredEntry: AgentConversationEntry?

    private var visibleEntries: [AgentConversationEntry] {
        Array(history.entries.suffix(24))
    }

    var body: some View {
        if history.detection != nil && !visibleEntries.isEmpty {
            ZStack(alignment: .trailing) {
                if let hoveredEntry {
                    preview(for: hoveredEntry)
                        .offset(x: -28)
                        .transition(.opacity)
                }

                VStack(spacing: 3) {
                    ForEach(visibleEntries) { entry in
                        Button {
                            surfaceView.focusAndScroll(to: entry)
                        } label: {
                            Capsule()
                                .fill(markerColor(for: entry))
                                .frame(width: 5, height: 10)
                                .frame(width: 18, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            hoveredEntry = isHovered ? entry : nil
                        }
                        .accessibilityLabel(
                            "\(entry.kind.displayName): \(entry.preview)")
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 3)
                .background(.thinMaterial, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 5)
            .animation(.easeOut(duration: 0.12), value: hoveredEntry)
        }
    }

    private func preview(for entry: AgentConversationEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.kind.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.preview)
                .font(.caption)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .frame(width: 220, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .shadow(radius: 4, y: 2)
        .allowsHitTesting(false)
    }

    private func markerColor(for entry: AgentConversationEntry) -> Color {
        switch entry.kind {
        case .user: return .accentColor
        case .assistant: return .secondary
        }
    }
}
