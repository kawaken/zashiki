# Developing Zashiki

This document describes technical details for developing Zashiki, trimmed
down from upstream Ghostty's own `HACKING.md` to the parts that are still
relevant to a private, macOS-only fork.

```shell
git clone https://github.com/kawaken/zashiki
cd zashiki
```

When you're developing, it's very likely that you will want to build a
_debug_ build to diagnose issues more easily. This is already the default for
Zig builds, so simply run `zig build` **without any `-Doptimize` flags**.

| Command          | Description                                                                                        |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `zig build run`  | Runs Ghostty                                                                                       |
| `zig build test` | Runs unit tests (accepts `-Dtest-filter=<filter>` to only run tests whose name matches the filter) |

## Xcode Version and SDKs

Building the Ghostty macOS app requires that Xcode, the macOS SDK,
the iOS SDK, and Metal Toolchain are all installed.

A common issue is that the incorrect version of Xcode is either
installed or selected. Use the `xcode-select` command to
ensure that the correct version of Xcode is selected:

```shell-session
sudo xcode-select --switch /Applications/Xcode.app
```

> [!IMPORTANT]
>
> Main branch development of Ghostty requires **Xcode 26 and the macOS 26 SDK**.
>
> You do not need to be running on macOS 26 to build Ghostty, you can
> still use Xcode 26 on macOS 15 stable.

## AI and Agents

`.agents/commands` has some vetted prompts for common tasks that have been
shown to produce good results, inherited from upstream Ghostty.

- `/gh-issue <number/url>` - Produces a prompt for diagnosing a GitHub
  issue, explaining the problem, and suggesting a plan for resolving it.
  Requires `gh` to be installed with read-only access to the repo.

## Logging

On macOS, logging to the macOS unified log is available and enabled by
default. Use the system `log` CLI to view Ghostty's logs:
`sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'`.

Ghostty's logging can be configured in two ways. The first is by what
optimization level Ghostty is compiled with. If Ghostty is compiled with `Debug`
optimizations debug logs will be output to `stderr`. If Ghostty is compiled with
any other optimization the debug logs will not be output to `stderr`.

Ghostty also checks the `GHOSTTY_LOG` environment variable. It can be used
to control which destinations receive logs. Ghostty currently defines two
destinations:

- `stderr` - logging to `stderr`.
- `macos` - logging to macOS's unified log (has no effect on non-macOS platforms).

Combine values with a comma to enable multiple destinations. Prefix a
destination with `no-` to disable it. Enabling and disabling destinations
can be done at the same time. Setting `GHOSTTY_LOG` to `true` will enable all
destinations. Setting `GHOSTTY_LOG` to `false` will disable all destinations.

## Linting

### Prettier

Docs and resources (not including Zig code) are linted using
[Prettier](https://prettier.io) with out-of-the-box settings. If you are
modifying anything Prettier will lint, install it locally and run this
from the repo root before you commit:

```
prettier --write .
```

### ShellCheck

Bash scripts are checked with [ShellCheck](https://www.shellcheck.net/).
[Install it](https://github.com/koalaman/shellcheck#user-content-installing)
and run:

```
shellcheck \
    --check-sourced \
    --severity=warning \
    $(find . \( -name "*.sh" -o -name "*.bash" \) -type f ! -path "./zig-out/*" ! -path "./macos/build/*" ! -path "./.git/*" | sort)
```

### SwiftLint

Swift code is linted using [SwiftLint](https://github.com/realm/SwiftLint). If
you are modifying Swift code, install it locally and run this from the repo
root before you commit:

```
swiftlint lint --fix
```

To check for violations without auto-fixing:

```
swiftlint lint --strict
```
