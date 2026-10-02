import GhosttyKit

extension FullscreenMode {
    /// Initialize from a Zashiki fullscreen action.
    static func from(ghostty: ghostty_action_fullscreen_e) -> Self? {
        return switch ghostty {
        case GHOSTTY_FULLSCREEN_NATIVE:
                .native

        default:
            nil
        }
    }
}
