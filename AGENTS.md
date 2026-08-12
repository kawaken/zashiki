# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Project Context

This is **Zashiki**, [@kawaken](https://github.com/kawaken)'s personal fork
of [Ghostty](https://github.com/ghostty-org/ghostty), maintained as an
ongoing product rather than a one-off patch set:

- macOS-only (no other platforms planned)
- Actively incorporates improvements aimed at Japanese-language
  input/IME (e.g. ATOK preedit styling)
- Develops fork-specific features independently (e.g. the Markdown
  preview pane)
- Does **not** always track upstream. Divergence from
  `ghostty-org/ghostty`, or a change that would make a future upstream
  merge harder, is not by itself a reason to avoid or reject a change.
  Upstream changes are adopted selectively when useful, not
  automatically.

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
sudo log stream --level debug --predicate 'subsystem=="dev.kawaken.zashiki"'
```

The `GHOSTTY_LOG` environment variable controls log destinations (`stderr`,
`macos`); prefix with `no-` to disable, comma-separate to combine, or use
`true`/`false` to enable/disable all.

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- Feature/implementation plan docs (not yet built, or design notes for a
  change in progress): `plan/`
- Write-ups of what actually happened for completed plans, including how
  it diverged from the plan: `docs/history/`

Once a plan's PR is merged, delete the `plan/*.md` file. If what actually
happened differed from the plan in a way worth remembering, write a short
`docs/history/*.md` first (see existing files there for the format) — plain
delete-and-forget is fine if there's nothing worth capturing. This keeps
`plan/` limited to work that's actually still in flight.
