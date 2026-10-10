import SwiftUI

/// The tab bar for a terminal window. Tabs live inside the window (see
/// `TerminalTab`), so this is drawn by us rather than by macOS.
struct TerminalTabBar: View {
    @ObservedObject var ghostty: Zashiki.App

    let tabs: [TerminalTab]
    let selectedTab: TerminalTab

    let onSelect: (TerminalTab) -> Void
    let onClose: (TerminalTab) -> Void
    let onAction: (TerminalTabAction, TerminalTab) -> Void
    let onMove: (UUID, TerminalTab, Bool) -> Void
    let onNewTab: () -> Void

    /// True when a split in the selected tab is zoomed.
    var isZoomed: Bool = false
    var onResetZoom: () -> Void = {}

    /// Space to leave for the window buttons when the bar is in the window's
    /// top-left corner.
    var windowButtonsInset: CGFloat = 0

    static let height: CGFloat = WindowTopRow.height
    private static let maximumTabWidth: CGFloat = 240

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
                    canCloseOthers: tabs.count > 1,
                    canCloseRight: index < tabs.count - 1,
                    onSelect: { onSelect(tab) },
                    onClose: { onClose(tab) },
                    onAction: { onAction($0, tab) },
                    onMove: { onMove($0, tab, $1) })
                    .frame(maxWidth: Self.maximumTabWidth, maxHeight: .infinity)

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

            WindowDragHandle()
                .frame(minWidth: 80, maxWidth: .infinity, maxHeight: .infinity)

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
