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

This repository supports multiple agents and tasks running in parallel. Use the
following rule: `1 task = 1 branch = 1 worktree`.

- Start each task from the latest `origin/main`. When creating a work environment
  from the primary checkout, run `git fetch origin` first, then create the branch
  and worktree from `origin/main`. Do not use a stale local `main` as the base
- Do not share a branch or worktree between tasks or agents

### Worktree checks at task start

At the start of a task, determine whether the current directory is the primary
checkout or a task-specific worktree.

- If already inside a task-specific worktree, use it as-is. When the execution
  environment has created the worktree, do not create another worktree or nest a
  worktree inside it
- If in the primary checkout, do not begin making changes there. Run
  `git fetch origin`, create a task-specific branch and worktree from the latest
  `origin/main`, and perform all subsequent editing, testing, and commits in the
  new worktree
- Do not check out a branch that is already in use by another worktree, or modify
  or remove a worktree used by another agent

If it is unclear whether the current worktree or branch is safe to use for the
task, inspect its state before modifying existing work.

- Treat `main` as read-only. Do not make implementation, documentation, plan, or
  history changes directly on it. Each task must use its own worktree and branch
- Use a flat, descriptive branch name without prefixes or namespaces such as
  `codex/` or `kawaken/`; do not use slash-separated branch hierarchies. Examples:
  `markdown-preview` and `fix-ime-preedit`. Do not use or edit existing worktrees
  or changes belonging to another session; modify only the worktree assigned to
  the current task
- Submit changes from the dedicated branch as a PR and merge them into `main`
  through the PR. Do not commit or push directly to `main`
- Remove a worktree after its corresponding PR has been merged. To clean only
  build artifacts, use `make clean` rather than invoking `rm -rf` directly. To
  remove a worktree, use `git worktree remove --force` (`-f -f` if it is locked).
  Before removing it, confirm that no other session is using it and that it has
  no uncommitted changes

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

## Release

Before pushing a release tag (`v*.*.*`), add an entry to `CHANGELOG.md`
summarizing user-facing changes since the previous release. Keep it short —
a flat bullet list per version, not a PR-by-PR dump (GitHub's auto-generated
release notes already cover that). Include changes that don't show up in
README.md's feature list too (e.g. platform-support changes, removals).

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
