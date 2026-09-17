import SwiftUI

/// Renders a Markdown document's FrontMatter entries as a two-column
/// key/value table, shown above the rendered body in the preview pane.
struct FrontMatterTableView: View {
    let entries: [MarkdownFrontMatter.Entry]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                GridRow {
                    Text(entry.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.value)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
