import SwiftUI
import Textual

/// An `AttachmentLoader` that only loads images referenced via `file://`
/// URLs (resolved against the previewed Markdown file's directory).
///
/// Markdown shown in this pane can reference arbitrary URLs in image
/// links, and Textual's default image loader (`URLAttachmentLoader`) will
/// happily fetch `http(s)://` URLs over the network. That would violate
/// this feature's "no external network calls" requirement, so this loader
/// rejects anything that doesn't resolve to a local file.
struct MarkdownPreviewImageLoader: AttachmentLoader {
    private let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    func attachment(
        for url: URL,
        text: String,
        environment: ColorEnvironmentValues
    ) async throws -> MarkdownPreviewImageAttachment {
        let resolved = URL(string: url.absoluteString, relativeTo: baseURL) ?? url
        guard resolved.isFileURL else {
            throw MarkdownPreviewImageLoaderError.disallowedScheme(resolved.scheme)
        }
        guard let nsImage = NSImage(contentsOf: resolved) else {
            throw MarkdownPreviewImageLoaderError.unreadableImage
        }

        return MarkdownPreviewImageAttachment(
            image: Image(nsImage: nsImage),
            size: nsImage.size,
            altText: text
        )
    }
}

enum MarkdownPreviewImageLoaderError: Error {
    case disallowedScheme(String?)
    case unreadableImage
}

/// A minimal image `Attachment`. Deliberately avoids depending on any of
/// Textual's internal attachment types (e.g. `ImageAttachment`, which is
/// not public) — this stores only value types so it stays trivially
/// `Sendable`/`Hashable`.
struct MarkdownPreviewImageAttachment: Attachment {
    let image: Image
    let size: CGSize
    let altText: String

    var description: String { altText }

    var body: some View {
        image
            .resizable()
            .scaledToFit()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        guard let proposedWidth = proposal.width, size.width > 0 else { return size }
        let aspect = size.width / size.height
        let width = min(proposedWidth, size.width)
        let height = width / aspect
        return CGSize(width: width, height: height)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.altText == rhs.altText && lhs.size == rhs.size
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(altText)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }
}
