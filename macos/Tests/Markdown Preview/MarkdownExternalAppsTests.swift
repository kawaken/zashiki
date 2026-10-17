import Foundation
import Testing
@testable import Zashiki

struct MarkdownExternalAppsTests {
    private func store() throws -> MarkdownExternalApps {
        let defaults = try #require(UserDefaults(suiteName: "MarkdownExternalAppsTests.\(UUID().uuidString)"))
        return MarkdownExternalApps(defaults: defaults)
    }

    @Test func presetsIncludeObsidianAndVSCode() throws {
        let store = try store()
        #expect(store.configuration.apps.map(\.id) == ["obsidian", "vscode"])
        for app in store.configuration.apps { try app.validate() }
        #expect(store.configuration.defaultApp?.id == "obsidian")
    }

    @Test func urlsEncodePathsAndQueryValuesWithoutChangingTheFile() throws {
        let file = URL(fileURLWithPath: "/notes/日本語 & draft?#%+;=/a%20b.md")
        let obsidian = MarkdownExternalApp.presets[0]
        let vscode = MarkdownExternalApp.presets[1]
        let obsidianURL = try obsidian.url(for: file)
        let obsidianComponents = try #require(URLComponents(url: obsidianURL, resolvingAgainstBaseURL: false))
        #expect(obsidianComponents.queryItems == [URLQueryItem(name: "path", value: file.path)])
        #expect(obsidianURL.absoluteString.contains("path=%2Fnotes%2F"))
        #expect(obsidianComponents.fragment == nil)

        let vscodeURL = try vscode.url(for: file)
        #expect(vscodeURL.host == "file")
        #expect(vscodeURL.path == file.path)
        #expect(vscodeURL.query == nil)
        #expect(vscodeURL.fragment == nil)
        #expect(vscodeURL.absoluteString.contains("/a%2520b.md"))
    }

    @Test func invalidTemplatesCannotBeSaved() throws {
        let store = try store()
        let initial = store.configuration
        for template in ["", "app://open", "relative/{path}", "{path}://open",
                         "app://open?file={unknown}",
                         "app://open?file={path}#{path}"] {
            var app = MarkdownExternalApp.presets[0]
            app.urlTemplate = template
            #expect(throws: Error.self) { try store.save(app) }
            #expect(store.configuration == initial)
        }
        var app = MarkdownExternalApp.presets[0]
        app.name = "  "
        #expect(throws: Error.self) { try store.save(app) }
    }

    @Test func editingDefaultsAndEmptyListsSurviveReloading() throws {
        let defaults = try #require(UserDefaults(suiteName: "MarkdownExternalAppsTests.\(UUID().uuidString)"))
        let store = MarkdownExternalApps(defaults: defaults)
        var custom = MarkdownExternalApp(
            id: UUID().uuidString, name: "Custom", urlTemplate: "custom://open?file={path}&mode=preview"
        )
        try store.save(custom)
        store.setDefault(id: custom.id)
        custom.name = "Renamed"
        try store.save(custom)
        #expect(store.configuration.apps.count == 3)
        #expect(store.configuration.defaultApp?.name == "Renamed")
        #expect(MarkdownExternalApps(defaults: defaults).configuration == store.configuration)

        store.remove(id: custom.id)
        #expect(store.configuration.defaultID == "obsidian")
        for app in store.configuration.apps { store.remove(id: app.id) }
        #expect(store.configuration.apps.isEmpty)
        #expect(store.configuration.defaultApp == nil)
        let reloaded = MarkdownExternalApps(defaults: defaults)
        #expect(reloaded.configuration.apps.isEmpty)
        try reloaded.save(MarkdownExternalApp.presets[1])
        #expect(reloaded.configuration.defaultID == "vscode")
        reloaded.setDefault(id: "missing")
        #expect(reloaded.configuration.defaultID == "vscode")
    }
}
