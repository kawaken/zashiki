import SwiftUI
import Cocoa

// For testing.
struct ColorizedZashikiIconView: View {
    var body: some View {
        Image(nsImage: ColorizedZashikiIcon(
            screenColors: [.purple, .blue],
            ghostColor: .yellow,
            frame: .aluminum
        ).makeImage(in: .main)!)
    }
}
