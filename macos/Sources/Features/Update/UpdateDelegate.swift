import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }

        // Sparkle supports a native concept of "channels" but it requires that
        // you share a single appcast file. We don't want to do that so we
        // do this instead.
        switch appDelegate.ghostty.config.autoUpdateChannel {
        // A tip appcast is not published yet. This URL intentionally returns
        // no updates until the nightly release workflow is introduced.
        case .tip: return "https://github.com/kawaken/zashiki/releases/download/tip/appcast.xml"
        case .stable:
            return "https://github.com/kawaken/zashiki/releases/latest/download/appcast.xml"
        }
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }
}
