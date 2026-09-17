import Foundation

/// Parses the YAML FrontMatter block (if any) from the top of a Markdown
/// document, separating it from the remaining body.
///
/// Only flat `key: value` entries are supported. Nested maps, arrays, and
/// multi-line values are not parsed as structured YAML; lines that don't
/// match `key: value` are simply skipped rather than causing a parse
/// failure, since the goal is a best-effort key/value table rather than a
/// full YAML parser.
enum MarkdownFrontMatter {
    /// A single FrontMatter entry, in document order.
    struct Entry: Equatable {
        let key: String
        let value: String
    }

    /// Splits `text` into FrontMatter entries and the remaining body.
    ///
    /// `text` is only treated as having FrontMatter if it starts with a
    /// `---` line followed by a later `---` line. Otherwise (no opening
    /// fence, or an unterminated one) `entries` is empty and `body` is
    /// `text` unchanged, so callers can render it exactly as before.
    static func parse(_ text: String) -> (entries: [Entry], body: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]

        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([], text)
        }
        lines = lines.dropFirst()

        guard let closingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            return ([], text)
        }

        let frontMatterLines = lines[..<closingIndex]
        let bodyLines = lines[(closingIndex + 1)...]

        let entries = frontMatterLines.compactMap(parseEntry)
        let body = bodyLines.joined(separator: "\n")

        return (entries, body)
    }

    private static func parseEntry<S: StringProtocol>(_ line: S) -> Entry? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }

        let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        var value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2 {
            for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) {
                value = String(value.dropFirst().dropLast())
                break
            }
        }

        return Entry(key: key, value: value)
    }
}
