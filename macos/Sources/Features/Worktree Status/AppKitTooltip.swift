import AppKit
import SwiftUI

/// An AppKit view that exposes a native tooltip without participating in hit
/// testing. SwiftUI's `help` modifier is kept for accessibility, while this
/// bridge makes the tooltip reliable inside the custom ScrollView/LazyVStack
/// used by Worktree Status.
private final class PassthroughTooltipView: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct AppKitTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> PassthroughTooltipView {
        let view = PassthroughTooltipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ view: PassthroughTooltipView, context: Context) {
        view.toolTip = text
    }
}

private struct AppKitTooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay {
            AppKitTooltipView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Adds a native AppKit tooltip while preserving SwiftUI hit testing.
    func appKitTooltip(_ text: String) -> some View {
        modifier(AppKitTooltipModifier(text: text))
    }
}
