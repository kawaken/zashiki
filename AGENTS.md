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
  once its required checks and review requirements are satisfied, except when
  the PR has the `needs-verification` label. A PR with `needs-verification`
  must remain open without AutoMerge until the human completes hands-on
  verification and removes the label. Do not use squash or rebase merges
  unless the user explicitly requests one. If AutoMerge cannot be enabled,
  check the reason and report it instead of merging manually without
  confirmation.

## Public-Facing Work

Do not include personal environment paths, configuration, or setup details in
public PRs, commits, issues, or plans.

## Release

Before creating a release tag (`v*.*.*`), review the user-facing changes since
the previous release and update `CHANGELOG.md`. Summarize the changes from the
user's perspective instead of simply copying PR titles.

Version bumps follow a loose rule, not strict semver: a release that includes
any `feature`-labeled work bumps MINOR; a release with only `fix`-labeled or
internal changes bumps PATCH. Batch multiple merged features and fixes into a
single release freely — there is no need to cut a release per merged PR, and
release timing is independent of verification (hands-on verification happens
via PR build artifacts; see `needs-verification` below).

## Plan and Issue Lifecycle

Issues are the starting point for work. The user selects an Issue and asks an
agent to handle it; creating a Plan is not a prerequisite for creating an
Issue. The Issue should prioritize and describe the problem or desired outcome,
while the Plan is the source of truth for detailed design and implementation
decisions.

- Before starting work on an Issue, check it for an existing `wip` label and a
  recent claim comment — if another agent already claimed it, don't pick it up
  without an explicit handoff. This check applies while the work is still
  plan-only, so multiple sessions don't start from the same Issue.
- When claiming an Issue, add `wip` and post a comment identifying who is
  working on it: the agent/tool (e.g. Claude Code, Codex) and, if the tool
  exposes one, a deep link to the session. If the Issue is only being reported
  for someone else, do not claim it. Add `feature` or `fix` when the Issue is
  created or updated, based on whether the change is user-visible or fixes/
  cleans up existing behavior; unlike `wip`, that label stays after the work
  is done.
- After reviewing the Issue, create or update the Plan in `plan/` and refine it
  directly as the design changes. Commit and push the Plan, then open a draft
  PR for the user's review. Keep the `wip` claim while this expected review
  step is in progress.
- After the Plan review, implement and verify the change, commit and push it,
  and mark the PR ready for review. If hands-on verification is needed, the
  user adds `needs-verification` to the PR. If the user explicitly asks for
  planning-only work, release this session's `wip` claim after the Plan PR is
  handed off; do not remove another agent's label or claim.
- When creating a PR, write its body according to the PR template.
- Findings and surprises discovered during implementation go into the Plan
  first. Summarize important progress or decisions in the Issue, but do not
  require the Issue body to mirror the Plan.
- When implementation is complete, append the implementation decisions and CI
  findings worth keeping to the Plan, then move it from `plan/` to
  `docs/history/` in the same PR. Do not create a separate PR only to move the
  Plan. After creating the PR, enable AutoMerge and monitor it until it is
  merged unless the PR has `needs-verification`; keep that PR open and do not
  enable AutoMerge until hands-on verification is complete and the label is
  removed. If required checks, reviews, permissions, or another external
  condition prevent the merge, report the blocker clearly. Remove `wip` after
  the work completes.
- If the user asks to handle the Issue end-to-end, the draft-PR Plan review
  step may be folded into the same implementation flow.
- Don't close the issue yourself unless it's a documentation-only change
  with nothing to verify. For other changes, leave the close itself to the
  human, whether they close it directly or tell you to.
- Don't let a PR auto-close the issue (e.g. via "Closes #123" in the PR
  body). Close the issue explicitly, as its own step.
- If a PR carries a large enough change that it needs hands-on verification
  (visual/behavioral, beyond what CI already checks), add the
  `needs-verification` label to the PR itself, not the issue. This label makes
  the `build` job in
  `test.yml` build `Zashiki.app` and upload it as a workflow artifact, so
  the change can be downloaded and tested by hand without cutting a
  release. Mention the related issue number in the PR body so they stay
  linked (without a `Closes #123` keyword, per the rule above). Keep the PR
  open without AutoMerge while the label is present. After hands-on
  verification, remove the label and proceed with the normal merge flow.
