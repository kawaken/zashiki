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
}
