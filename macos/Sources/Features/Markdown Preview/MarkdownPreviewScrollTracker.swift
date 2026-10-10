import AppKit
import SwiftUI

/// Uses public NSScrollView APIs to preserve pixel offsets on macOS 13 too.
/// The view identity follows the history entry, so tab/history switches create
/// a fresh scroll view while live reloads keep the current one.
struct MarkdownPreviewScrollTracker: NSViewRepresentable {
    let position: MarkdownPreviewScrollPosition

    func makeNSView(context: Context) -> TrackerView { TrackerView(position: position) }
    func updateNSView(_ view: TrackerView, context: Context) { view.attachWhenReady() }

    final class TrackerView: NSView {
        private let position: MarkdownPreviewScrollPosition
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var restored = false
        private var attachmentPending = false

        init(position: MarkdownPreviewScrollPosition) {
            self.position = position
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachWhenReady()
        }

        func attachWhenReady() {
            guard observer == nil, !attachmentPending else { return }
            attachmentPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.attachmentPending = false
                guard self.window != nil, let scroll = self.enclosingScrollView else { return }
                self.scrollView = scroll
                let clip = scroll.contentView
                clip.postsBoundsChangedNotifications = true
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in
                    guard let self, self.restored else { return }
                    self.position.offset = max(0, clip.bounds.origin.y)
                }
                // SwiftUI lays out the newly selected document on the next turn.
                DispatchQueue.main.async { [weak self] in self?.restore() }
            }
        }

        private func restore() {
            guard let scrollView, window != nil else { return }
            scrollView.layoutSubtreeIfNeeded()
            let clip = scrollView.contentView
            let height = scrollView.documentView?.frame.height ?? 0
            let maximum = max(0, height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(position.offset, maximum)))
            scrollView.reflectScrolledClipView(clip)
            restored = true
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
