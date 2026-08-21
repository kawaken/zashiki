import Foundation

extension Zashiki {
    /// This is a delegate that should be applied to your global app delegate for GhosttyKit
    /// to perform app-global operations.
    protocol Delegate {
        /// Look up a surface within the application by ID.
        func zashikiSurface(id: UUID) -> SurfaceView?
    }
}
