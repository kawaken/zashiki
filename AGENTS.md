# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Commands

- **Build:** `zig build`
  - If you're on macOS and don't need to build the macOS app, use
    `-Demit-macos-app=false` to skip building the app bundle and speed up
    compilation.
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt .`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w .`

## Xcode

Building the macOS app requires Xcode, the macOS SDK, the iOS SDK, and Metal
Toolchain all installed. If the wrong Xcode version is selected, fix it with:

```shell-session
sudo xcode-select --switch /Applications/Xcode.app
```

## Logging

macOS unified logging is enabled by default. View logs with:

```shell-session
sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'
```

The `GHOSTTY_LOG` environment variable controls log destinations (`stderr`,
`macos`); prefix with `no-` to disable, comma-separate to combine, or use
`true`/`false` to enable/disable all.

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- Feature/implementation plan docs (not yet built, or design notes for a
  change in progress): `plan/`
