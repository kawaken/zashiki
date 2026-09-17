import Testing
@testable import Zashiki

struct MarkdownFrontMatterTests {
    @Test func testParsesFlatEntries() {
        let text = """
        ---
        title: Hello World
        author: kawaken
        ---
        # Body

        Some text.
        """

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries == [
            .init(key: "title", value: "Hello World"),
            .init(key: "author", value: "kawaken"),
        ])
        #expect(result.body == "# Body\n\nSome text.")
    }

    @Test func testStripsQuotesFromValues() {
        let text = """
        ---
        title: "Quoted Title"
        note: 'single quoted'
        ---
        body
        """

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries == [
            .init(key: "title", value: "Quoted Title"),
            .init(key: "note", value: "single quoted"),
        ])
    }

    @Test func testMissingClosingFenceFallsBackToOriginalText() {
        let text = """
        ---
        title: Hello

        # Body
        """

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries.isEmpty)
        #expect(result.body == text)
    }

    @Test func testNoOpeningFenceReturnsTextUnchanged() {
        let text = "# Just a heading\n\nNo front matter here."

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries.isEmpty)
        #expect(result.body == text)
    }

    @Test func testEmptyFrontMatterProducesNoEntries() {
        let text = """
        ---
        ---
        # Body
        """

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries.isEmpty)
        #expect(result.body == "# Body")
    }

    @Test func testLinesWithoutColonAreSkipped() {
        let text = """
        ---
        title: Hello
        tags:
          - one
          - two
        ---
        body
        """

        let result = MarkdownFrontMatter.parse(text)

        #expect(result.entries.contains(.init(key: "title", value: "Hello")))
        #expect(result.entries.contains(where: { $0.key == "tags" && $0.value.isEmpty }))
    }
}
