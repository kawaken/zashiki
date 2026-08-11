import Darwin
import Foundation

/// Watches a single file and invokes `onChange` when its content likely
/// changed, so `MarkdownPreviewModel` can call `reload()` automatically.
///
/// Two things make this more than a thin `DispatchSourceFileSystemObject`
/// wrapper:
///
/// - **Debouncing**: editors and tools (Claude Code included) often issue
///   several `write`/`extend` events for a single logical save. Those are
///   coalesced with an 80ms debounce before `onChange` fires.
/// - **Atomic saves**: many editors (vim's `:w`, and most "safe save"
///   implementations) don't write the watched file in place — they write a
///   temp file and `rename(2)` it over the original. That invalidates the
///   file descriptor this class has open, surfacing as a `.delete` or
///   `.rename` event. When that happens, the source is torn down and
///   `onChange` is called immediately, before a background retry loop
///   reopens the (possibly new) file at the same path. If the file was
///   genuinely deleted, `onChange` naturally reports that as an error via
///   `MarkdownPreviewModel.reload()`; once the file reappears, the retry
///   picks it back up and `onChange` fires again to clear the error.
final class MarkdownPreviewFileWatcher {
    private let url: URL
    private let onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var rearmWorkItem: DispatchWorkItem?

    private static let debounceInterval: TimeInterval = 0.08
    private static let rearmInterval: TimeInterval = 0.1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit {
        invalidate()
    }

    /// Stops watching. Safe to call multiple times.
    func invalidate() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
        source?.cancel()
        source = nil
    }

    /// Opens `url` and starts a `DispatchSourceFileSystemObject` on it. If
    /// the file can't be opened (e.g. it's been deleted), schedules a
    /// retry instead of giving up.
    private func arm() {
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRearm()
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        newSource.setEventHandler { [weak self] in
            self?.handle(newSource.data)
        }
        newSource.setCancelHandler {
            Darwin.close(fd)
        }
        newSource.resume()
        source = newSource

        // Re-report content on every successful (re)arm, not just the
        // first one, so recovering from a delete/rename picks up
        // whatever is now at `url`.
        onChange()
    }

    private func handle(_ mask: DispatchSource.FileSystemEvent) {
        if mask.contains(.delete) || mask.contains(.rename) {
            // The descriptor we're watching no longer refers to `url`
            // (atomic-save rename, or a real delete). Tear it down and
            // try to reattach; `arm()` reports back via `onChange` either
            // way (new content, or a "file not found" error).
            source?.cancel()
            source = nil
            scheduleRearm()
            return
        }
        if mask.contains(.write) || mask.contains(.extend) {
            scheduleReload()
        }
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    private func scheduleRearm() {
        rearmWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.arm()
        }
        rearmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.rearmInterval, execute: workItem)
    }
}
