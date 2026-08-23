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
- Does **not** track upstream. Divergence from `ghostty-org/ghostty`, or
  a change that would make a future upstream merge harder, is not by
  itself a reason to avoid or reject a change.
- **Never consult upstream on your own.** There is deliberately no
  `upstream` git remote, and you must not add one. Whether to adopt an
  upstream change is the maintainer's decision alone: they will judge it
  and tell you what to do. Do not fetch from, diff against, browse, or
  reason about `ghostty-org/ghostty` unless explicitly instructed to in
  that specific task.

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
- These three run automatically on staged files via a pre-commit hook
  (`.githooks/pre-commit`). One-time setup per clone:
  `git config core.hooksPath .githooks`.

## Git Worktree

- `main`は常に読み取り専用として扱い、実装・ドキュメント・plan/historyを含む変更を
  直接行わない。複数セッションが同じリポジトリを利用するため、作業開始時に必ず
  専用worktreeと作業ブランチを作成する
- ブランチ名には`codex/`接頭辞を付けない。既存のworktreeや他セッションの変更を
  使用・編集せず、作業対象のworktreeだけを変更する
- 変更は専用ブランチからPRとして提出し、mainへの反映はPRのマージで行う。例外的に
  mainへ直接コミット・pushしない
- 対応するPRがマージされたworktreeは削除する。ビルド生成物のみ掃除したい場合は
  `rm -rf` を直接叩かず `make clean` を使う。worktree自体を消す場合は
  `git worktree remove --force`（lock中なら `-f -f`）。削除前に他セッションが
  使用中でないか（lock状態・未コミット変更）を確認する

## Public-Facing Work (PRs, Commits, Issues)

This repo is public on GitHub. Anything written into a PR body, commit
message, or issue — including plan docs committed to the repo — is visible
to anyone, not just the maintainer.

- **Never publish details about the maintainer's personal environment or
  config state.** This includes: paths outside the repo (e.g. dotfiles
  locations, home-directory layout), the actual contents of their config
  file (theme, fonts, keybinds, etc.), or observations like "your config
  isn't currently loaded" / "this file doesn't exist on your machine".
  Findings phrased in the first person about the maintainer's own machine
  belong in chat, not in anything pushed to GitHub.
- This applies even when the finding is directly relevant to the task
  (e.g. "config search paths changed after rebrand") — describe the
  _code's_ behavior generically, not the maintainer's specific setup.
- If in doubt whether something is personal, ask before including it in
  a PR/commit rather than publishing and asking forgiveness.

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

The `ZASHIKI_LOG` environment variable controls log destinations (`stderr`,
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
