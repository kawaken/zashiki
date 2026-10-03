import SwiftUI

/// The tab bar for a terminal window. Tabs live inside the window (see
/// `TerminalTab`), so this is drawn by us rather than by macOS.
struct TerminalTabBar: View {
    @ObservedObject var ghostty: Zashiki.App

    let tabs: [TerminalTab]
    let selectedTab: TerminalTab

    let onSelect: (TerminalTab) -> Void
    let onClose: (TerminalTab) -> Void
    let onNewTab: () -> Void

    /// True when a split in the selected tab is zoomed.
    var isZoomed: Bool = false
    var onResetZoom: () -> Void = {}

    /// Space to leave for the window buttons when the bar is in the window's
    /// top-left corner.
    var windowButtonsInset: CGFloat = 0

    static let height: CGFloat = WindowTopRow.height

    var body: some View {
        HStack(spacing: 0) {
            if windowButtonsInset > 0 {
                Color.clear.frame(width: windowButtonsInset)
                Divider()
            }

            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TerminalTabItem(
                    tab: tab,
                    isSelected: tab === selectedTab,
                    shortcut: shortcut(forTabAt: index),
                    showsBellInTitle: ghostty.config.bellFeatures.contains(.title),
                    onSelect: { onSelect(tab) },
                    onClose: { onClose(tab) })

                Divider()
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .frame(width: Self.height, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .accessibilityLabel("New Tab")

            if isZoomed {
                Divider()
                Button(action: onResetZoom) {
                    Image("ResetZoom")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset Split Zoom")
                .accessibilityLabel("Reset Split Zoom")
            }
        }
        .frame(height: Self.height)
        .background(Color.primary.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The label for the `goto_tab` keybinding of the tab at `index`, if any.
    private func shortcut(forTabAt index: Int) -> String? {
        let number = index + 1
        guard number <= 9 else { return nil }
        guard let shortcut = ghostty.config.keyboardShortcut(for: "goto_tab:\(number)") else { return nil }
        return "\(shortcut)"
    }
}

private struct TerminalTabItem: View {
    @ObservedObject var tab: TerminalTab

    let isSelected: Bool
    let shortcut: String?
    let showsBellInTitle: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    private var title: String {
        tab.bell && showsBellInTitle ? "🔔 \(tab.title)" : tab.title
    }

    var body: some View {
        // The whole tab is a button so clicks select it. The close button sits
        // on top so it takes its own clicks.
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Keeps the title centered against the close button's space.
                Color.clear.frame(width: 16, height: 16)

                Spacer(minLength: 0)

                if let color = tab.color.displayColor {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: 0)

                Text(shortcut ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color.clear : Color.primary.opacity(isHovering ? 0.04 : 0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .padding(.leading, 8)
            .help("Close Tab")
            .accessibilityLabel("Close Tab")
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
