import AppKit
import SwiftUI
import Textual

/// The right-hand pane shown when a terminal window's Markdown preview is
/// visible. Shows a header (back/forward navigation, file name, close
/// button) plus the rendered Markdown, an empty state, or an error state.
struct MarkdownPreviewPane: View {
    @ObservedObject var model: MarkdownPreviewModel

    @State private var isHistoryPresented = false
    @FocusedValue(\.zashikiSurfaceCellSize) private var cellSize
    @Environment(\.zashikiLastFocusedSurface) private var lastFocusedSurface
    @AppStorage("MarkdownPreviewFontSizeOverride", store: .zashiki)
    private var markdownFontSizeOverride: Double = 0

    private var markdownFontSize: CGFloat {
        MarkdownPreviewFontSizePolicy.resolve(
            override: CGFloat(markdownFontSizeOverride),
            terminalCellHeight: MarkdownPreviewFontSizePolicy.terminalCellHeight(
                focused: cellSize?.height,
                lastFocused: lastFocusedSurface?.value?.cellSize.height
            ),
            fallbackSize: NSFont.systemFontSize
        )
    }

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
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoBack ? .primary : .tertiary)
            .disabled(!model.canGoBack)
            .help("Show Previous File")

            Button {
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canGoForward ? .primary : .tertiary)
            .disabled(!model.canGoForward)
            .help("Show Next File")

            Button {
                isHistoryPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.historyEntries.isEmpty ? .tertiary : .primary)
            .disabled(model.historyEntries.isEmpty)
            .help("Show Markdown Preview History")
            .popover(isPresented: $isHistoryPresented, arrowEdge: .top) {
                MarkdownPreviewHistoryList(model: model) {
                    model.go(toHistoryEntryAt: $0)
                    isHistoryPresented = false
                }
            }

            Button {
                isFontSizePresented.toggle()
            } label: {
                Image(systemName: "textformat.size")
            }
            .buttonStyle(.plain)
            .help("Markdown Preview Font Size")
            .popover(isPresented: $isFontSizePresented, arrowEdge: .top) {
                fontSizeControls
            }

            Text(model.fileURL?.lastPathComponent ?? "Markdown Preview")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.fileURL?.path ?? "")

            Spacer()

            Button(action: revealFileInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .disabled(model.fileURL == nil)
            .help("Reveal File in Finder")

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Markdown Preview")
        }
        .padding(.horizontal, 8)
        .frame(height: WindowTopRow.height)
    }

    @State private var isFontSizePresented = false

    private var fontSizeControls: some View {
        let fontSizeRange = Double(MarkdownPreviewFontSizePolicy.minimumSize)...Double(
            MarkdownPreviewFontSizePolicy.maximumSize
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Markdown Preview Font Size")
                .font(.headline)
            HStack {
                Text("\(Int(markdownFontSize)) pt")
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { Double(markdownFontSize) },
                        set: { markdownFontSizeOverride = $0 }
                    ),
                    in: fontSizeRange,
                    step: 1
                )
            }
            Button("Match Terminal") {
                markdownFontSizeOverride = 0
            }
            .disabled(markdownFontSizeOverride == 0)
        }
        .padding(14)
        .frame(width: 260)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let parsed = MarkdownFrontMatter.parse(model.content)
            let sections = MarkdownPreviewDocument.sections(for: parsed.body)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !parsed.entries.isEmpty {
                            FrontMatterTableView(
                                entries: parsed.entries,
                                fontSize: markdownFontSize
                            )
                            Divider()
                        }

                        ForEach(sections) { section in
                            StructuredText(
                                markdown: section.markdown,
                                baseURL: model.fileURL?.deletingLastPathComponent()
                            )
                            .textual.structuredTextStyle(.gitHub)
                            .textual.imageAttachmentLoader(
                                MarkdownPreviewImageLoader(baseURL: model.fileURL?.deletingLastPathComponent())
                            )
                            .textual.textSelection(.enabled)
                            .font(.system(size: markdownFontSize))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(section.id)
                        }
                    }
                    .background {
                        if let position = model.scrollPosition {
                            MarkdownPreviewScrollTracker(position: position)
                        }
                    }
                }
                .id(model.scrollPosition?.id)
                .environment(\.openURL, OpenURLAction { url in
                    openLink(url, sections: sections, using: proxy)
                })
            }
        }
    }

    private func openLink(
        _ url: URL,
        sections: [MarkdownPreviewDocumentSection],
        using proxy: ScrollViewProxy
    ) -> OpenURLAction.Result {
        if let fragment = url.fragment, isLocalFragment(url) {
            let anchor = fragment.removingPercentEncoding?.lowercased() ?? fragment.lowercased()
            let target = sections.first {
                $0.anchor?.lowercased() == anchor
            }

            guard let target else { return .discarded }
            withAnimation {
                proxy.scrollTo(target.id, anchor: .top)
            }
            return .handled
        }

        return NSWorkspace.shared.open(url) ? .handled : .discarded
    }

    private func isLocalFragment(_ url: URL) -> Bool {
        guard let fileURL = model.fileURL else { return false }
        guard let scheme = url.scheme else { return true }
        guard scheme == "file" else { return false }

        return url.path.isEmpty
            || url.path == fileURL.path
            || url.path == fileURL.deletingLastPathComponent().path
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

    private func revealFileInFinder() {
        guard let fileURL = model.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

private struct MarkdownPreviewHistoryList: View {
    @ObservedObject var model: MarkdownPreviewModel
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Markdown Preview History")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.historyEntriesNewestFirst) { entry in
                        Button {
                            select(entry.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: entry.id == model.currentHistoryIndex
                                    ? "checkmark"
                                    : "doc.text")
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.url.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Text(entry.url.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                entry.id == model.currentHistoryIndex
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 360, height: min(CGFloat(model.historyEntries.count * 58 + 54), 420))
    }
}
