import Foundation

enum MarkdownPreviewOpenAcknowledgement {
    static let queryItemName = "response"

    private static let filenamePrefix = "zashiki-preview-response-"
    private static let filenameSuffixLength = 22
    private static let allowedSuffixCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func responseURL(for path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let parent = url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard parent == temporaryDirectory else { return nil }

        let filename = url.lastPathComponent
        guard filename.hasPrefix(filenamePrefix) else { return nil }
        let suffix = filename.dropFirst(filenamePrefix.count)
        guard suffix.count == filenameSuffixLength,
              suffix.unicodeScalars.allSatisfy({ allowedSuffixCharacters.contains($0) }) else {
            return nil
        }
        return url
    }

    static func write(_ result: String, to path: String) throws {
        guard let url = responseURL(for: path) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try Data(result.utf8).write(to: url, options: .atomic)
    }
}
