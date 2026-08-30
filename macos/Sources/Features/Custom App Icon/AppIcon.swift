import AppKit
import System

/// The icon style for the Zashiki App.
enum AppIcon: Equatable, Codable, Sendable {
    case official
    /// Save full image data to avoid sandboxing issues
    case custom(_ iconFile: Data)
    case customStyle(_ icon: ColorizedZashikiIcon)

#if !DOCK_TILE_PLUGIN
    init?(config: Zashiki.Config) {
        switch config.macosIcon {
        case .official:
            return nil
        case .custom:
            if let data = try? Data(contentsOf: URL(filePath: config.macosCustomIcon, relativeTo: nil)) {
                self = .custom(data)
            } else {
                return nil
            }
        case .customStyle:
            guard let screenColors = config.macosIconScreenColor else {
                return nil
            }
            self = .customStyle(ColorizedZashikiIcon(screenColors: screenColors, frame: config.macosIconFrame))
        }
    }
#endif

    func image(in bundle: Bundle) -> NSImage? {
        switch self {
        case .official:
            return nil
        case let .custom(file):
            return NSImage(data: file)
        case let .customStyle(customIcon):
            return customIcon.makeImage(in: bundle)
        }
    }
}

#if !DOCK_TILE_PLUGIN
/// Making sure that `NSWorkspace.shared.setIcon` executes on only one thread at a time
actor AppIconUpdater {
    func update(icon: AppIcon?) {
        UserDefaults.zashiki.appIcon = icon
        // Notify DockTilePlugin to update dock icon
        DistributedNotificationCenter.default()
            .postNotificationName(
                .zashikiIconDidChange,
                object: nil,
                userInfo: nil,
                deliverImmediately: true,
            )

        NSWorkspace.shared.setIcon(
            icon?.image(in: .main),
            forFile: Bundle.main.bundlePath,
        )
        NSWorkspace.shared.noteFileSystemChanged(Bundle.main.bundlePath)
    }
}
#endif
