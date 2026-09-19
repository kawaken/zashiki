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
