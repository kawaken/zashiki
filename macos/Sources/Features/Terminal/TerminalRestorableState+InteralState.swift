import AppKit

extension TerminalRestorableState {
    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    struct InternalState<ViewType: NSView & Codable & Identifiable>: Codable {
        // MARK: - Version 5 (1.2.3)
        let focusedSurface: String?
        let surfaceTree: SplitTree<ViewType>

        // MARK: - Version 7 (1.3.0)
        let effectiveFullscreenMode: FullscreenMode?
        let tabColor: TerminalTabColor?
        let titleOverride: String?

        // MARK: - Version 8 (tabs inside the window)

        /// Every tab in the window, in display order. Nil in older data, where
        /// a window was a single tab described by the fields above. The fields
        /// above always describe the selected tab.
        var tabs: [TabState]?
        var selectedTabIndex: Int?

        /// The state of one tab.
        struct TabState: Codable {
            let focusedSurface: String?
            let surfaceTree: SplitTree<ViewType>
            let tabColor: TerminalTabColor?
            let titleOverride: String?
        }

        /// The tabs to restore: the saved tabs, or a single tab built from
        /// the fields of older data.
        var restorableTabs: [TabState] {
            if let tabs, !tabs.isEmpty { return tabs }
            return [.init(
                focusedSurface: focusedSurface,
                surfaceTree: surfaceTree,
                tabColor: tabColor,
                titleOverride: titleOverride)]
        }
    }
}

extension TerminalRestorableState.InternalState where ViewType == Zashiki.SurfaceView {
    init(from controller: TerminalController) {
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            effectiveFullscreenMode: controller.fullscreenStyle?.fullscreenMode,
            tabColor: controller.selectedTab.color,
            titleOverride: controller.titleOverride,
            tabs: controller.tabs.map { tab in
                .init(
                    focusedSurface: tab.focusedSurface?.id.uuidString,
                    surfaceTree: tab.surfaceTree,
                    tabColor: tab.color,
                    titleOverride: tab.titleOverride)
            },
            selectedTabIndex: controller.tabs.firstIndex(where: { $0 === controller.selectedTab })
        )
    }
}
