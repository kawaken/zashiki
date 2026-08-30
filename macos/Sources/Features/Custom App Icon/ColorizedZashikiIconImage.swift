import SwiftUI

extension View {
    /// Returns the Zashiki icon to use for views.
    func zashikiIconImage() -> Image {
        #if os(macOS)
        // Grab the icon from the running application. This is the best way
        // I've found so far to get the proper icon for our current icon
        // tinting and so on with macOS Tahoe
        if let icon = NSRunningApplication.current.icon {
            return Image(nsImage: icon)
        }

        if let icon = NSApp.applicationIconImage {
            return Image(nsImage: icon)
        }
        #endif

        // Fall back to a generic image for previews and non-macOS builds.
        return Image(systemName: "terminal")
    }
}
