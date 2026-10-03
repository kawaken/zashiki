import SwiftUI

/// The Agents pane shown on the left side of a terminal window. Agent
/// detection is kept alive only while this pane is visible.
struct AgentStatusPane: View {
    @ObservedObject var model: AgentStatusModel

    /// Every Surface in the terminal window's tabGroup (every tab, not just
    /// the focused one). The model is shared by all tabs in the window.
    let surfaces: [Zashiki.SurfaceView]

    /// Space for the window buttons when this pane is in the window's
    /// top-left corner.
    @Environment(\.windowButtonsInset) private var windowButtonsInset

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: surfaces.map(\.id)) {
            await monitorAgents()
        }
        .onDisappear {
            model.clear()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.secondary)
            Text("Agents")
                .font(.headline)
                .lineLimit(1)
            if !model.agents.isEmpty {
                Text("\(model.agents.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Agents")
        }
        .padding(.horizontal, 8)
        .padding(.leading, windowButtonsInset)
        .frame(height: WindowTopRow.height)
    }

    @ViewBuilder
    private var content: some View {
        if model.agents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No agents found.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.agents) { agent in
                        AgentStatusRowView(agent: agent) {
                            focus(agent.surface)
                        }
                        .padding(.horizontal, 8)
                        Divider()
                    }
                }
            }
        }
    }

    private func monitorAgents() async {
        while !Task.isCancelled {
            model.refresh(surfaces: surfaces)
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }
        }
    }

    private func focus(_ surface: Zashiki.SurfaceView) {
        surface.window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        Zashiki.moveFocus(to: surface)
    }
}
