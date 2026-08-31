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

- If an assigned task worktree is already available, use it; do not create a new
  worktree or nest one inside it.
- Git tooling or an agent may provide a worktree in a detached HEAD state. For
  tasks that require commits or pushes, create a dedicated flat branch from the
  current worktree at the start of the work. From the CLI, use
  `git switch -c <task-branch>`.
- If you are already in a task worktree with a dedicated branch, use it.
- Do not share a branch or worktree between multiple tasks or agents at the same
  time.
- Use a flat, descriptive branch name without prefixes such as `codex/` or
  `kawaken/`; do not use slash-separated branch hierarchies.
- Do not use or edit worktrees or changes belonging to other tasks; use only the
  worktree assigned to the current task.
- Keep `main` free of feature changes. Updating it with the fast-forward-only
  command above is allowed; all feature changes belong on a dedicated task
  branch and must be submitted through a PR.
- After creating a PR, enable GitHub AutoMerge with
  `gh pr merge --auto --merge` so the PR is merged with a regular merge commit
  once its required checks and review requirements are satisfied. Do not use
  squash or rebase merges unless the user explicitly requests one. If
  AutoMerge cannot be enabled, check the reason and report it instead of
  merging manually without confirmation.

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
- Creating or updating an Issue is not the same as starting implementation.
  However, when this session owns the Issue while creating, refining,
  committing, or moving its plan, add `wip` and a claim comment as a temporary
  ownership lock. The `wip` label means that the Issue is actively held by a
  session; it does not imply that implementation has already started.
  If the Issue is only being reported for someone else, do not claim it.
- The issue tracks progress; the plan file stays the source of truth for
  design. When the plan file changes, update the issue too — this doesn't
  have to happen in the same commit, but keep the two from drifting apart.
- Before starting work on an Issue, check it for an existing `wip` label and a
  recent claim comment — if another agent already claimed it, don't pick it up
  without an explicit handoff. This check applies even when the existing work
  is still plan-only, so multiple sessions don't start from the same Issue.
- When claiming an Issue, add `wip` and post a comment identifying who is
  working on it: the agent/tool (e.g. Claude Code, Codex) and, if the tool
  exposes one, a deep link to the session. When implementation starts after
  plan-only work, keep the existing `wip` claim and update the comment if
  needed.
- Findings and surprises discovered while implementing go into the plan file
  first, then into the issue (since the issue should reflect the plan).
- Once a plan has been created and committed, continue through implementation,
  verification, PR creation, and merge unless the user explicitly asks for
  planning-only work. After creating the PR, enable AutoMerge and monitor it
  until it is merged. If required checks, reviews, permissions, or another
  external condition prevent the merge, report the blocker clearly.
- If the user explicitly asks for planning-only work, or implementation has
  not started after the plan is committed, keep the Issue open and remove this
  session's `wip` label so another session can take it. Post a short comment
  stating that the planning claim has been released; do not remove another
  agent's label or claim.
- When work completes, move the plan to `docs/history/`, remove it from
  `plan/`, and append the implementation decisions or CI findings worth
  keeping. Then remove the `wip` label.
- Don't close the issue yourself unless it's a documentation-only change
  with nothing to verify. Anything with behavior to verify (code, CI,
  workflow changes) gets the `needs-verification` label instead — leave the
  close itself to the human, whether they close it directly or tell you to.
- Don't let a PR auto-close the issue (e.g. via "Closes #123" in the PR
  body). Close the issue explicitly, as its own step.
