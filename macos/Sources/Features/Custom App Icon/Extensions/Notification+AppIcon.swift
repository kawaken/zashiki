import AppKit

extension Notification.Name {
    /// Distributed Notification for DockTilePlugin to update icon
    ///
    /// Zashiki -> DockTilePlugin
    static let zashikiIconDidChange = Notification.Name("dev.kawaken.zashiki.iconDidChange")
}
