# Zashiki

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)'s private, macOS-only fork of
[Ghostty](https://github.com/ghostty-org/ghostty).

## Fork-specific features

- **ATOK / Japanese IME preedit styling** — the clause currently being
  converted gets a thicker underline than the rest of the preedit text,
  matching how ATOK itself distinguishes it.
- **Markdown preview pane** — toggle a preview pane (`Cmd+Shift+M`) that
  renders Markdown natively in SwiftUI (no WebKit). Open a file from the
  CLI via `scripts/zashiki-md-preview <file>` (custom `zashiki://` URL
  scheme); the pane live-updates as the file changes. Handy for
  previewing files an agent like Claude Code is writing to.
