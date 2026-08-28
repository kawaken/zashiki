# Zashiki

<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
</p>

[@kawaken](https://github.com/kawaken)'s macOS-only fork of
[Ghostty](https://github.com/ghostty-org/ghostty).

## Features

- Japanese IME support with thicker underlines for the currently converted ATOK preedit clause,
  and surrounding-text context (via `NSTextInputClient`) so IMEs like ATOK can use the text
  already typed on the current line for more accurate conversion.
- Native SwiftUI Markdown preview (`Cmd+Shift+M`) with live file updates.
  Markdown files can also be opened from the CLI with
  `zashiki +markdown-preview <file>`, targeting the originating terminal window.

See [README.ja.md](README.ja.md) for the Japanese version.
