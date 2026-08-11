import SwiftUI
import Textual
import UniformTypeIdentifiers

/// The right-hand pane shown when a terminal window's Markdown preview is
/// visible. Shows a header (file name, close button) plus the rendered
/// Markdown, an empty state, or an error state.
struct MarkdownPreviewPane: View {
    @ObservedObject var model: MarkdownPreviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(model.fileURL?.lastPathComponent ?? "Markdown Preview")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Markdown Preview")
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage {
            statusMessage(systemImage: "exclamationmark.triangle", message: errorMessage)
        } else if model.fileURL == nil {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No file open")
                    .foregroundStyle(.secondary)
                Button("Open File...", action: openFile)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                StructuredText(
                    markdown: model.content,
                    baseURL: model.fileURL?.deletingLastPathComponent()
                )
                .textual.structuredTextStyle(.gitHub)
                .textual.imageAttachmentLoader(
                    MarkdownPreviewImageLoader(baseURL: model.fileURL?.deletingLastPathComponent())
                )
                .textual.textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusMessage(systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.open(url: url)
    }
}
