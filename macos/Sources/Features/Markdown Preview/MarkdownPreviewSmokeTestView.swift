import SwiftUI
import Textual

// TEMPORARY: Step 1 smoke test for the Textual SPM package (GFM tables, code
// syntax highlighting, dark mode). Not wired into any UI yet — exists only
// so `zig build` exercises SPM package resolution + linking. Delete once
// Step 1 verification is done and MarkdownPreviewPane.swift lands.
struct MarkdownPreviewSmokeTestView: View {
    private let markdown = """
        # Zashiki Markdown Preview

        This is a **smoke test** for the `Textual` package.

        | Column A | Column B |
        | -------- | -------- |
        | 1        | 2        |

        ```swift
        let x = 1
        ```
        """

    var body: some View {
        ScrollView {
            StructuredText(markdown: markdown)
                .textual.structuredTextStyle(.gitHub)
                .padding()
        }
    }
}
