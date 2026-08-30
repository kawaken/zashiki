## Project Context

This is **Zashiki**, [@kawaken](https://github.com/kawaken)'s personal fork
of [Ghostty](https://github.com/ghostty-org/ghostty), maintained as an
ongoing product rather than a one-off patch set:

- macOS-only (no other platforms planned)
- Actively incorporates improvements aimed at Japanese-language
  input/IME (e.g. ATOK preedit styling)
- Upstream is not followed automatically. Adopt only the changes that are
  individually judged necessary, while continuing independent feature
  development. Unless explicitly instructed, do not fetch, inspect, compare,
  or import `ghostty-org/ghostty`, and do not add an `upstream` remote.

## Commands

- **Development task runner:** `just`
  - Run `just` or `just help` to list the available development tasks.
  - `just build`, `just build-core`, and `just run` cover the common build
    workflows.
  - `just test-fast` is the PR-sized check; use `just test` for the full suite
    including macOS XCTest. Use `just test-filter "<test name>"` for a focused
    Zig test run.
  - `just lint`, `just format`, and `just ci` cover formatting and CI checks.
  - Install `just` with Homebrew (`brew install just`). Set `DEVELOPER_DIR`
    when a task must use a particular Xcode; tasks do not change the system-wide
    `xcode-select` setting.
- **Build:** `zig build`
  - If you're on macOS and don't need to build the macOS app, use
    `-Demit-macos-app=false` to skip building the app bundle and speed up
    compilation.
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `git ls-files -z '*.zig' | xargs -0 zig fmt`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w .`
- These three run automatically on staged files via a pre-commit hook
  (`.githooks/pre-commit`). One-time setup per clone:
  `git config core.hooksPath .githooks`.

## Git Worktree

This repository supports multiple agents and tasks running in parallel. Use the
following rule: `1 task = 1 branch = 1 worktree`.

- Start each task from the latest `origin/main`.
- Do not share a branch or worktree between multiple tasks or agents at the same
  time.
- Use a flat, descriptive branch name without prefixes such as `codex/` or
  `kawaken/`; do not use slash-separated branch hierarchies.
- Do not use or edit worktrees or changes belonging to other tasks; use only the
  worktree assigned to the current task.
- Keep `main` read-only. Make changes on a dedicated branch and submit them
  through a PR.
- After creating a PR, enable GitHub AutoMerge with `gh pr merge --auto` so the
  PR is merged automatically once its required checks and review requirements
  are satisfied. If AutoMerge cannot be enabled, check the reason and report it
  instead of merging manually without confirmation.

## Public-Facing Work

Do not include personal environment paths, configuration, or setup details in
public PRs, commits, issues, or plans.

## Release

Before creating a release tag (`v*.*.*`), review the user-facing changes since
the previous release and update `CHANGELOG.md`. Summarize the changes from the
user's perspective instead of simply copying PR titles.

## Plan and Issue Lifecycle

Plans start as local files in `plan/`, refined through discussion. Update the
file directly whenever the plan changes.

- Once a plan is reasonably settled, create a GitHub Issue for it. Use the
  plan's title and content as the issue's title and body, and link back to
  the plan file from the issue.
- The issue tracks progress; the plan file stays the source of truth for
  design. When the plan file changes, update the issue too — this doesn't
  have to happen in the same commit, but keep the two from drifting apart.
- When starting work on an issue, add the `wip` label.
- Findings and surprises discovered while implementing go into the plan file
  first, then into the issue (since the issue should reflect the plan).
- When work completes, move the plan to `docs/history/`, remove it from
  `plan/`, and append the implementation decisions or CI findings worth
  keeping. Then close the issue.
- Don't let a PR auto-close the issue (e.g. via "Closes #123" in the PR
  body). Close the issue explicitly, as its own step.
