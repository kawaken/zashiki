# macOS Zashiki Application

- Use `swiftlint` for formatting and linting Swift code.
- Use `zig build` to build the macOS app (it wraps `xcodebuild -scheme
  Zashiki` internally, see `src/build/ZashikiXcodebuild.zig`).
  - Build: `zig build` (Debug) or `zig build -Doptimize=ReleaseFast` (Release)
  - Output: `macos/build/<configuration>/Zashiki.app` (e.g. `macos/build/Debug/Zashiki.app`)
- Run unit tests with `zig build test`
