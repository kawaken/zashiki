set shell := ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# Running `just` shows the same task list as `just help`.
default: help

# Build the Debug Zashiki app.
build:
    zig build

# Build the core without the macOS app bundle.
build-core:
    zig build -Demit-macos-app=false

# Build and launch the development app.
run:
    zig build run

# Update the generated GLAD loader from glad.zip.
glad:
    #!/usr/bin/env bash
    if [[ ! glad.zip -nt vendor/glad/include/glad/gl.h || ! -f vendor/glad/include/glad/glad.h ]]; then
        test -f glad.zip || { echo 'glad.zip is required; place the generated archive in the repository root.' >&2; exit 1; }
        rm -rf vendor/glad
        mkdir -p vendor/glad
        unzip glad.zip -dvendor/glad
        find vendor/glad -type f -exec touch '{}' +
        echo '#include <glad/gl.h>' > vendor/glad/include/glad/glad.h
    fi

# Run the complete test suite, including macOS XCTest.
test:
    zig build test

# Run the PR-sized test suite: Zig tests and Swift compilation without XCTest.
test-fast:
    zig build test -Dmacos-app-xctest=false

# Run Zig tests matching NAME.
test-filter NAME:
    zig build test -Dtest-filter='{{ NAME }}'

# Check formatting for tracked Zig files only.
_zig-fmt-check:
    git ls-files -z '*.zig' | xargs -0 zig fmt --check

# Format tracked Zig files only.
_zig-fmt:
    git ls-files -z '*.zig' | xargs -0 zig fmt

# Check Zig and Swift formatting.
lint: _zig-fmt-check
    swiftlint lint --strict

# Format Zig and Swift files in place.
format: _zig-fmt
    swiftlint lint --strict --fix

# Remove generated build artifacts.
clean:
    rm -rf zig-out .zig-cache macos/build macos/GhosttyKit.xcframework

# Show the Zashiki macOS unified log and follow new entries.
logs:
    log stream --level debug --predicate 'subsystem == "dev.kawaken.zashiki"'

# Show available development tasks and their intended use.
help:
    @echo "Zashiki development tasks:"
    @just --list --unsorted
    @echo
    @echo "Set DEVELOPER_DIR to select a specific Xcode without changing system settings."

# Run the same checks used by pull requests.
ci: test-fast lint

# Build the source distribution tarball.
dist:
    zig build dist

# Validate the source distribution tarball.
distcheck:
    zig build distcheck

# Show the Xcode selected for macOS tasks.
xcode-version:
    @printf 'DEVELOPER_DIR=%s\n' "${DEVELOPER_DIR:-default}"
    xcodebuild -version
