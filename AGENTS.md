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

- Always write the plan file first, then create the issue from it — even for
  a bug or finding discovered mid-task. There is no "this is urgent" or
  "this is just a quick bug report" exception: this is a personal project,
  not an on-call rotation, so nothing here is time-critical enough to skip
  the plan file. Do not create a GitHub Issue directly without a plan file
  backing it.
- Once a plan is reasonably settled, create a GitHub Issue for it. Use the
  plan's title and content as the issue's title and body, and link back to
  the plan file from the issue.
- The issue tracks progress; the plan file stays the source of truth for
  design. When the plan file changes, update the issue too — this doesn't
  have to happen in the same commit, but keep the two from drifting apart.
- Before starting work, check the issue for an existing `wip` label and a
  recent claim comment — if another agent already claimed it, don't pick it
  up. This is how agents avoid clobbering each other's in-progress work.
- When starting work, add the `wip` label and post a comment identifying who
  is working on it: the agent/tool (e.g. Claude Code, Codex) and, if the
  tool exposes one, a deep link to the session. This makes the claim visible
  to both other agents and the human.
- Findings and surprises discovered while implementing go into the plan file
  first, then into the issue (since the issue should reflect the plan).
- When work completes, move the plan to `docs/history/`, remove it from
  `plan/`, and append the implementation decisions or CI findings worth
  keeping. Then remove the `wip` label.
- Don't close the issue yourself unless it's a documentation-only change
  with nothing to verify. Anything with behavior to verify (code, CI,
  workflow changes) gets the `needs-verification` label instead — leave the
  close itself to the human, whether they close it directly or tell you to.
- Don't let a PR auto-close the issue (e.g. via "Closes #123" in the PR
  body). Close the issue explicitly, as its own step.
