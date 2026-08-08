<!-- LOGO -->
<h1>
<p align="center">
  <img src="macos/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="Zashiki icon" width="128">
  <br>Zashiki
</h1>
  <p align="center">
    A personal, macOS-only fork of <a href="https://github.com/ghostty-org/ghostty">Ghostty</a>.
    <br />
    <a href="#about">About</a>
    ·
    <a href="#fork-specific-features">Fork-specific features</a>
    ·
    <a href="LOCAL_PATCH.md">Building &amp; upstream tracking</a>
    ·
    <a href="https://ghostty.org">Ghostty upstream</a>
  </p>
</p>

## About

**Zashiki** (座敷 — a formal tatami room in a traditional Japanese house, the
one you show guests into) is [@kawaken](https://github.com/kawaken)'s personal
fork of [Ghostty](https://github.com/ghostty-org/ghostty), the terminal
emulator built by Mitchell Hashimoto and its contributors. It exists for one
reason: to be a terminal that fits how I actually work day to day, without
waiting on upstream for changes that are too personal, too niche, or too
half-baked to belong in a project used by millions.

It is **not** a competing project, a replacement, or something meant for
general distribution — it's a "for myself" tool, built on top of Ghostty's
excellent, standards-compliant, fast core (see
[Ghostty's own README](https://github.com/ghostty-org/ghostty#readme) and
[About Ghostty](https://ghostty.org/docs/about) for what that core actually
does — architecture, performance, `libghostty`, the whole story. There's no
point duplicating it here).

The working agreement with upstream is: **track it, don't diverge from it.**
`main` merges in upstream releases regularly rather than rebasing or
cherry-picking, additions are kept as isolated as possible, and anything
that would meaningfully complicate merging back in gets a second look before
it lands. See [LOCAL_PATCH.md](LOCAL_PATCH.md) for the exact workflow, the
list of every file this fork has touched, and how to build it yourself.

This fork is macOS-only. Linux/GTK, Windows, and the various packaging
formats (Flatpak, Snap, Nix) that upstream supports are not built, tested,
or maintained here.

## Fork-specific features

- **ATOK / Japanese IME preedit styling** — while composing text with a
  Japanese IME (ATOK and others), the clause currently being converted gets
  a visibly thicker underline than the rest of the preedit text, matching
  how ATOK itself distinguishes it. Upstream Ghostty renders all preedit
  clauses with the same thin underline.
- **Markdown preview pane** (planned, not yet built) — a toggleable pane
  showing a live-rendered preview of a Markdown file, aimed at watching
  Claude Code write to a file without leaving the terminal. See
  [MARKDOWN_PREVIEW_PLAN.md](MARKDOWN_PREVIEW_PLAN.md) for the design.

Everything else — windowing, tabs, splits, Quick Terminal, Command Palette,
AppleScript support, and so on — is stock Ghostty, unmodified.

## Building

There's no distribution channel for Zashiki (no notarized releases, no
Sparkle auto-update feed) — you build it yourself. See
[LOCAL_PATCH.md](LOCAL_PATCH.md) for setup, build, and install instructions,
and the [`Release` GitHub Actions workflow](.github/workflows/release.yml)
for how ad-hoc-signed builds get zipped up.

For anything not specific to this fork — general Zig/Swift development
questions, the wider architecture — [CONTRIBUTING.md](CONTRIBUTING.md) and
[HACKING.md](HACKING.md) (both inherited from upstream) are still accurate.

## Crash Reports

Ghostty has a built-in crash reporter that will generate and save crash
reports to disk. The crash reports are saved to the `$XDG_STATE_HOME/ghostty/crash`
directory. If `$XDG_STATE_HOME` is not set, the default is `~/.local/state`.
**Crash reports are _not_ automatically sent anywhere off your machine.**

Crash reports are only generated the next time the app is started after a
crash. If it crashed and you want to generate a crash report, you must
restart it at least once. You should see a message in the log that a
crash report was generated.

> [!NOTE]
>
> Use the `ghostty +crash-report` CLI command to get a list of available crash
> reports.

Crash reports end in the `.ghosttycrash` extension and are in
[Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/) — this
fork hasn't set up its own Sentry project, so the upload command below
(inherited from upstream, unchanged) would send the report to **upstream
Ghostty's** Sentry project, not anywhere specific to this fork. Only run it
if you're comfortable with that, or point `SENTRY_DSN` at your own project
instead:

```shell-session
SENTRY_DSN=https://e914ee84fd895c4fe324afa3e53dac76@o4507352570920960.ingest.us.sentry.io/4507850923638784 sentry-cli send-envelope --raw <path to crash report>
```

> [!WARNING]
>
> The crash report can contain sensitive information. The report doesn't
> purposely contain sensitive information, but it does contain the full
> stack memory of each thread at the time of the crash. This information
> is used to rebuild the stack trace but can also contain sensitive data
> depending on when the crash occurred.
