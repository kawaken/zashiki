import Foundation

extension UserDefaults {
    static let claudeCodeHistoryAutoScrollKey = "ClaudeCodeHistoryAutoScroll"

    static var zashikiSuite: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["ZASHIKI_USER_DEFAULTS_SUITE"]
        #else
        nil
        #endif
    }

    static var zashiki: UserDefaults {
        zashikiSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    var claudeCodeHistoryAutoScrollEnabled: Bool {
        get { bool(forKey: Self.claudeCodeHistoryAutoScrollKey) }
        set { set(newValue, forKey: Self.claudeCodeHistoryAutoScrollKey) }
    }
}
