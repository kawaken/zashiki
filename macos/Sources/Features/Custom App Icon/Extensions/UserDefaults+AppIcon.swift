import AppKit

extension UserDefaults {
    private static let customIconKeyOld = "CustomGhosttyIcon"
    private static let customIconKeyGhostty = "CustomGhosttyIcon2"
    private static let customIconKeyNew = "CustomZashikiIcon"

    var appIcon: AppIcon? {
        get {
            // Always remove our old pre-docktileplugin values.
            defer {
                removeObject(forKey: Self.customIconKeyOld)
            }

            // Check if we have the current key first.
            if let data = data(forKey: Self.customIconKeyNew) {
                return try? JSONDecoder().decode(AppIcon.self, from: data)
            }

            // Fall back to the pre-rename key (from before the Zashiki
            // rebrand) so an existing custom icon selection isn't lost.
            // Migrate it forward to the new key so this only runs once.
            guard let legacyData = data(forKey: Self.customIconKeyGhostty) else {
                return nil
            }
            set(legacyData, forKey: Self.customIconKeyNew)
            removeObject(forKey: Self.customIconKeyGhostty)
            return try? JSONDecoder().decode(AppIcon.self, from: legacyData)
        }

        set {
            guard let newData = try? JSONEncoder().encode(newValue) else {
                return
            }

            set(newData, forKey: Self.customIconKeyNew)
        }
    }
}
