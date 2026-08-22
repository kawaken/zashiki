# Zashiki

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)'s macOS-only fork of
[Ghostty](https://github.com/ghostty-org/ghostty). The app name, bundle ID,
CLI, configuration, and resource paths are separated for Zashiki.

## Features

- Japanese IME support with thicker underlines for the currently converted
  ATOK preedit clause.
- Native SwiftUI Markdown preview (`Cmd+Shift+M`) with live file updates.
  Open a file from a shell or AI agent with:

  ```sh
  open "zashiki://markdown-preview/open?path=<encoded-path>&surface=$ZASHIKI_SURFACE_ID"
  ```

  Omit `surface` to target the most recently active window.

- Sparkle update infrastructure with signed appcasts published through GitHub
  Releases. Automatic checks remain disabled until Developer ID signing and
  notarization are available.

## Development

Building the macOS app requires Xcode, the macOS SDK, and the Metal Toolchain.

```sh
zig build
zig build -Doptimize=ReleaseFast -Dxcframework-target=native -Demit-macos-app=true
zig build test -Dtest-filter=<test-name>
```

Build products are installed under `zig-out/`. Swift builds use
`macos/Zashiki.xcodeproj`.

## Releases

The Release workflow runs when a `v*.*.*` tag is pushed or when dispatched
manually from GitHub Actions. Merging to `main` alone does not create a
release. Manual runs require a `version` input such as `v0.3.0`.

The workflow attaches `Zashiki-*-macos.zip` and a signed `appcast.xml` to the
GitHub Release. The `SPARKLE_PRIVATE_KEY` Actions secret must be configured
before releasing. Keep the private key out of the repository and retain a
separate encrypted backup.

See [README.ja.md](README.ja.md) for the Japanese version.
