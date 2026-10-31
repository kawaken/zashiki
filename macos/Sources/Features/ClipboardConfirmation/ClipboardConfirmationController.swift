import Foundation
import Cocoa
import SwiftUI
import GhosttyKit

/// This initializes a clipboard confirmation warning window. The window itself
/// WILL NOT show automatically and the caller must show the window via
/// showWindow, beginSheet, etc.
class ClipboardConfirmationController: NSWindowController {
    override var windowNibName: NSNib.Name? { "ClipboardConfirmation" }

    let completion: ClipboardRequestCompletion
    let contents: String
    let request: Zashiki.ClipboardRequest
    weak private var delegate: ClipboardConfirmationViewDelegate?

    init(completion: ClipboardRequestCompletion, contents: String, request: Zashiki.ClipboardRequest, delegate: ClipboardConfirmationViewDelegate) {
        self.completion = completion
        self.contents = contents
        self.request = request
        self.delegate = delegate
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    // MARK: - NSWindowController

    override func windowDidLoad() {
        guard let window = window else { return }

        switch request {
        case .paste:
            window.title = "Warning: Potentially Unsafe Paste"
        case .osc_52_read, .osc_52_write:
            window.title = "Authorize Clipboard Access"
        }

        window.contentView = NSHostingView(rootView: ClipboardConfirmationView(
            contents: contents,
            request: request,
            delegate: delegate
        ))
    }
}
