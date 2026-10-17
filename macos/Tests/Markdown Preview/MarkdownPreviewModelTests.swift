import Testing
import Foundation
@testable import Zashiki

struct MarkdownPreviewModelTests {
    /// Creates a temporary Markdown file and returns its URL. The file is
    /// removed when the test process exits; tests don't need to clean it up.
    private func temporaryFile(_ contents: String = "") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func zashikiCLIResponseOnlyUsesDedicatedTemporaryFiles() {
        let validPath = "/tmp/zashiki-cli-response-abcdefghijklmnopqrstuv"
        #expect(ZashikiCLIResponse.responseURL(for: validPath)?.path == validPath)
        #expect(ZashikiCLIResponse.responseURL(
            for: "/tmp/other-response-abcdefghijklmnopqrstuv"
        ) == nil)
        #expect(ZashikiCLIResponse.responseURL(
            for: "/tmp/zashiki-cli-response-../../outside"
        ) == nil)
        #expect(ZashikiCLIResponse.responseURL(
            for: "relative/zashiki-cli-response-abcdefghijklmnopqrstuv"
        ) == nil)
    }

    @Test func testMarkdownPreviewSectionsCreateGitHubStyleAnchors() {
        let sections = MarkdownPreviewDocument.sections(for: """
            Introduction

            ## Getting Started

            [Details](#getting-started)

            ## Getting Started
            """)

        #expect(sections.map(\.anchor) == [nil, "getting-started", "getting-started-1"])
        #expect(sections[1].id == "getting-started")
        #expect(sections[2].id == "getting-started-1")
    }

    @Test func testMarkdownPreviewSectionsIgnoreHeadingsInsideCodeFences() {
        let sections = MarkdownPreviewDocument.sections(for: """
            # Actual Heading

            ```markdown
            # Not a Heading
            ```

            ## Another Heading
            """)

        #expect(sections.map(\.anchor) == ["actual-heading", "another-heading"])
        #expect(sections[0].markdown.contains("# Not a Heading"))
    }

    @Test func testMarkdownPreviewSectionsSupportExplicitHeadingAnchors() {
        for ending in ["", "\n"] {
            let sections = MarkdownPreviewDocument.sections(for: "# Release Notes {#release-notes}" + ending)

            #expect(sections.count == 1)
            #expect(sections[0].anchor == "release-notes")
            #expect(sections[0].markdown == "# Release Notes" + ending)
        }
    }

    @Test func testOpenSingleFileHasNoHistory() throws {
        let model = MarkdownPreviewModel()
        let url = try temporaryFile()

        model.open(url: url)

        #expect(model.fileURL == url)
        #expect(!model.canGoBack)
        #expect(!model.canGoForward)
    }

    @Test func relativePathsUseComponentsAndKeepUnicodeAndSpaces() {
        let examples: [(String, String, String)] = [
            ("/project", "/project/docs/design.md", "docs/design.md"),
            ("/project/src", "/project/docs/design.md", "../docs/design.md"),
            ("/project", "/project-other/design.md", "../project-other/design.md"),
            ("/project/作業 notes", "/project/作業 notes/仕様 draft.md", "仕様 draft.md"),
            ("/", "/project/docs/design.md", "project/docs/design.md"),
            ("/project/./src/..", "/project/docs/../design.md", "design.md")
        ]
        for (base, file, expected) in examples {
            let entry = MarkdownPreviewHistoryEntry(
                id: 0, url: URL(fileURLWithPath: file), baseDirectoryURL: URL(fileURLWithPath: base)
            )
            #expect(entry.relativePath == expected)
        }
        let withoutBase = MarkdownPreviewHistoryEntry(
            id: 0, url: URL(fileURLWithPath: "/project/design.md"), baseDirectoryURL: nil
        )
        #expect(withoutBase.relativePath == nil)
    }

    @Test func copyBaseBelongsToEachOpenAndFollowsHistoryNavigation() throws {
        let model = MarkdownPreviewModel()
        let file = try temporaryFile("# Document")
        let parent = file.deletingLastPathComponent()
        let otherBase = parent.appendingPathComponent("another-directory", isDirectory: true)

        model.open(url: file, baseDirectoryURL: parent)
        model.open(url: file, baseDirectoryURL: otherBase)
        #expect(model.relativePath == "../\(file.lastPathComponent)")
        #expect(model.historyEntries.map(\.baseDirectoryURL) == [parent, otherBase])

        model.goBack()
        #expect(model.baseDirectoryURL == parent)
        #expect(model.relativePath == file.lastPathComponent)
        model.goForward()
        #expect(model.baseDirectoryURL == otherBase)
        model.go(toHistoryEntryAt: 0)
        model.reload()
        model.close()
        model.toggle()
        #expect(model.relativePath == file.lastPathComponent)

        // An open without CLI metadata must not inherit an earlier base.
        model.open(url: file)
        #expect(model.baseDirectoryURL == nil)
        #expect(model.relativePath == nil)
        #expect(model.historyEntries.map(\.baseDirectoryURL) == [parent, nil])
        #expect(!model.canGoForward)
        model.goBack()
        #expect(model.baseDirectoryURL == parent)
    }

    @Test func markdownCopyUsesFullSourceAndRejectsReadErrors() throws {
        let model = MarkdownPreviewModel()
        #expect(model.markdownForCopy == nil)
        let source = "---\ntitle: 仕様\n---\n\n# Heading\n\n**Markdown**\n"
        let file = try temporaryFile(source)
        model.open(url: file)
        #expect(model.markdownForCopy == source)
        try "".write(to: file, atomically: true, encoding: .utf8)
        model.reload()
        #expect(model.markdownForCopy == "")

        model.open(url: file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString))
        #expect(model.errorMessage != nil)
        #expect(model.markdownForCopy == nil)
    }

    @Test func testGoBackAndForward() throws {
        let model = MarkdownPreviewModel()
        let first = try temporaryFile()
        let second = try temporaryFile()

        model.open(url: first)
        model.open(url: second)
        #expect(model.fileURL == second)
        #expect(model.canGoBack)
        #expect(!model.canGoForward)

        model.goBack()
        #expect(model.fileURL == first)
        #expect(!model.canGoBack)
        #expect(model.canGoForward)

        model.goForward()
        #expect(model.fileURL == second)
        #expect(model.canGoBack)
        #expect(!model.canGoForward)
    }

    @Test func testGoBackKeepsLaterHistoryEntries() throws {
        let model = MarkdownPreviewModel()
        let files = try (0..<4).map { _ in try temporaryFile() }

        for file in files {
            model.open(url: file)
        }
        model.goBack()

        #expect(model.fileURL == files[2])
        #expect(model.historyEntries.map(\.url) == files)
        #expect(model.currentHistoryIndex == 2)
        #expect(model.canGoForward)
    }

    @Test func testMarkdownPreviewFontSizeFollowsTerminalByDefault() {
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 0,
            terminalCellHeight: 20,
            fallbackSize: 13
        ) == 16)
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 0,
            terminalCellHeight: nil,
            fallbackSize: 13
        ) == 13)
    }

    @Test func testMarkdownPreviewFontSizeUsesLastFocusedTerminalWhenPreviewIsFocused() {
        let terminalCellHeight = MarkdownPreviewFontSizePolicy.terminalCellHeight(
            focused: nil,
            lastFocused: 20
        )

        #expect(terminalCellHeight == 20)
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 0,
            terminalCellHeight: terminalCellHeight,
            fallbackSize: 13
        ) == 16)
    }

    @Test func testMarkdownPreviewFontSizePrefersFocusedTerminalAndRejectsInvalidSizes() {
        #expect(MarkdownPreviewFontSizePolicy.terminalCellHeight(
            focused: 24,
            lastFocused: 20
        ) == 24)
        #expect(MarkdownPreviewFontSizePolicy.terminalCellHeight(
            focused: 0,
            lastFocused: 20
        ) == 20)
        #expect(MarkdownPreviewFontSizePolicy.terminalCellHeight(
            focused: nil,
            lastFocused: 0
        ) == nil)
    }

    @Test func testMarkdownPreviewFontSizeOverrideIsIndependentAndClamped() {
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 18,
            terminalCellHeight: 30,
            fallbackSize: 13
        ) == 18)
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 5,
            terminalCellHeight: 30,
            fallbackSize: 13
        ) == MarkdownPreviewFontSizePolicy.minimumSize)
        #expect(MarkdownPreviewFontSizePolicy.resolve(
            override: 40,
            terminalCellHeight: 30,
            fallbackSize: 13
        ) == MarkdownPreviewFontSizePolicy.maximumSize)
    }

    @Test func testHistoryEntriesExposeFilesInOpenOrder() throws {
        let model = MarkdownPreviewModel()
        let first = try temporaryFile()
        let second = try temporaryFile()

        model.open(url: first)
        model.open(url: second)

        #expect(model.historyEntries.map(\.url) == [first, second])
        #expect(model.currentHistoryIndex == 1)
    }

    @Test func testHistoryEntriesCanBeDisplayedNewestFirst() throws {
        let model = MarkdownPreviewModel()
        let first = try temporaryFile()
        let second = try temporaryFile()
        let third = try temporaryFile()

        model.open(url: first)
        model.open(url: second)
        model.open(url: third)

        #expect(model.historyEntriesNewestFirst.map(\.url) == [third, second, first])
        #expect(model.historyEntriesNewestFirst.map(\.id) == [2, 1, 0])
        #expect(model.currentHistoryIndex == 2)
    }

    @Test func testSelectingHistoryEntryDoesNotAddEntry() throws {
        let model = MarkdownPreviewModel()
        let first = try temporaryFile()
        let second = try temporaryFile()
        let third = try temporaryFile()

        model.open(url: first)
        model.open(url: second)
        model.open(url: third)
        model.go(toHistoryEntryAt: 0)

        #expect(model.fileURL == first)
        #expect(model.historyEntries.map(\.url) == [first, second, third])
        #expect(model.currentHistoryIndex == 0)
        #expect(model.canGoForward)
    }

    @Test func testGoBackBeyondStartIsNoOp() throws {
        let model = MarkdownPreviewModel()
        let url = try temporaryFile()

        model.open(url: url)
        model.goBack()
        model.goBack()

        #expect(model.fileURL == url)
        #expect(!model.canGoBack)
    }

    @Test func testOpenAfterGoBackTruncatesForwardHistory() throws {
        let model = MarkdownPreviewModel()
        let first = try temporaryFile()
        let second = try temporaryFile()
        let third = try temporaryFile()

        model.open(url: first)
        model.open(url: second)
        model.goBack()
        model.open(url: third)

        #expect(model.fileURL == third)
        #expect(model.canGoBack)
        #expect(!model.canGoForward)

        model.goBack()
        #expect(model.fileURL == first)
        #expect(!model.canGoBack)
        #expect(model.canGoForward)
    }
    @Test func scrollPositionsFollowHistoryEntriesAndTabs() throws {
        let first = MarkdownPreviewModel()
        let second = MarkdownPreviewModel()
        let url = try temporaryFile("# Document")
        first.open(url: url)
        let original = try #require(first.scrollPosition)
        original.offset = 120
        first.open(url: url)
        #expect(first.scrollPosition?.offset == 0)
        first.scrollPosition?.offset = 240
        first.goBack()
        #expect(first.scrollPosition === original)
        #expect(first.scrollPosition?.offset == 120)
        first.goForward()
        #expect(first.scrollPosition?.offset == 240)
        second.open(url: url)
        #expect(second.scrollPosition?.offset == 0)
        first.close()
        first.toggle()
        first.reload()
        #expect(first.scrollPosition?.offset == 240)
    }

    @Test func newNavigationDiscardsForwardScrollPosition() throws {
        let model = MarkdownPreviewModel()
        let url = try temporaryFile()
        model.open(url: url)
        model.open(url: url)
        let discarded = try #require(model.scrollPosition)
        discarded.offset = 500
        model.goBack()
        model.open(url: url)
        #expect(model.scrollPosition !== discarded)
        #expect(model.scrollPosition?.offset == 0)
        // Late events from the old document cannot change the new entry.
        discarded.offset = 900
        #expect(model.scrollPosition?.offset == 0)
    }

}
