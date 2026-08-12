import Foundation

extension UserDefaults {
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
}
