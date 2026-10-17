import AppKit
import Combine
import Foundation

struct MarkdownExternalApp: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var urlTemplate: String

    static let presets: [Self] = [
        .init(id: "obsidian", name: "Obsidian", urlTemplate: "obsidian://open?path={path}"),
        .init(id: "vscode", name: "Visual Studio Code", urlTemplate: "vscode://file{path}")
    ]

    enum ValidationError: LocalizedError {
        case emptyName
        case invalidTemplate
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter an app name."
            case .invalidTemplate: return "Enter a URL with {path} in its path or query."
            case .invalidFile: return "Choose a local file."
            }
        }
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyName
        }
        _ = try url(for: URL(fileURLWithPath: "/preview.md"))
    }

    /// Encode the same absolute path differently in URL paths and query values.
    /// In particular, Obsidian requires slashes in query values to be encoded.
    func url(for fileURL: URL) throws -> URL {
        guard fileURL.isFileURL else { throw ValidationError.invalidFile }
        let template = urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = template.replacingOccurrences(of: "{path}", with: "")
        guard template.contains("{path}"), !remainder.contains("{"), !remainder.contains("}") else {
            throw ValidationError.invalidTemplate
        }
        let marker = "/zashiki-path-\(UUID().uuidString)"
        guard var components = URLComponents(string: template.replacingOccurrences(of: "{path}", with: marker)),
              let scheme = components.scheme, !scheme.isEmpty,
              !scheme.contains(marker), components.host?.contains(marker) != true,
              components.fragment?.contains(marker) != true,
              components.percentEncodedPath.contains(marker)
                || components.percentEncodedQuery?.contains(marker) == true else {
            throw ValidationError.invalidTemplate
        }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedPath = fileURL.path.addingPercentEncoding(
            withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: "/"))
        ), let encodedQuery = fileURL.path.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw ValidationError.invalidFile
        }
        components.percentEncodedPath = components.percentEncodedPath.replacingOccurrences(of: marker, with: encodedPath)
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: marker, with: encodedQuery)
        guard let url = components.url else { throw ValidationError.invalidTemplate }
        return url
    }
}

struct MarkdownExternalAppConfiguration: Codable, Equatable {
    var apps: [MarkdownExternalApp]
    var defaultID: String?

    static let initial = Self(apps: MarkdownExternalApp.presets, defaultID: "obsidian")

    var defaultApp: MarkdownExternalApp? { apps.first { $0.id == defaultID } }

    mutating func normalizeDefault() {
        if defaultApp == nil { defaultID = apps.first?.id }
    }
}

final class MarkdownExternalApps: ObservableObject {
    static let shared = MarkdownExternalApps(defaults: .zashiki)
    private static let storageKey = "MarkdownExternalApps"

    @Published private(set) var configuration: MarkdownExternalAppConfiguration
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        var configuration = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(MarkdownExternalAppConfiguration.self, from: $0) }
            ?? .initial
        configuration.normalizeDefault()
        self.configuration = configuration
    }

    func save(_ app: MarkdownExternalApp) throws {
        try app.validate()
        var updated = configuration
        if let index = updated.apps.firstIndex(where: { $0.id == app.id }) {
            updated.apps[index] = app
        } else {
            updated.apps.append(app)
        }
        update(updated)
    }

    func remove(id: String) {
        var updated = configuration
        updated.apps.removeAll { $0.id == id }
        update(updated)
    }

    func setDefault(id: String) {
        guard configuration.apps.contains(where: { $0.id == id }) else { return }
        var updated = configuration
        updated.defaultID = id
        update(updated)
    }

    private func update(_ configuration: MarkdownExternalAppConfiguration) {
        var updated = configuration
        updated.normalizeDefault()
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: Self.storageKey)
        self.configuration = updated
    }

    func open(_ app: MarkdownExternalApp, fileURL: URL) -> String? {
        do {
            guard fileURL.isFileURL else { throw MarkdownExternalApp.ValidationError.invalidFile }
            try app.validate()
            let url = try app.url(for: fileURL)
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                return "No application is registered for \(app.name)'s URL scheme. Open the app or check its URL template."
            }
            return NSWorkspace.shared.open(url) ? nil : "Could not open the file in \(app.name)."
        } catch {
            return error.localizedDescription
        }
    }
}
