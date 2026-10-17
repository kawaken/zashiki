import AppKit
import SwiftUI

final class MarkdownExternalAppsSettingsController: NSWindowController {
    static let shared = MarkdownExternalAppsSettingsController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Markdown External Apps"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MarkdownExternalAppsSettings(store: .shared))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MarkdownExternalAppsSettings: View {
    @ObservedObject var store: MarkdownExternalApps
    @State private var selectedID: String?
    @State private var editingApp: MarkdownExternalApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an app for the Markdown preview's open button.")
                .foregroundStyle(.secondary)

            Picker("Default App", selection: Binding(
                get: { store.configuration.defaultID ?? "" },
                set: { store.setDefault(id: $0) }
            )) {
                if store.configuration.apps.isEmpty { Text("No apps configured").tag("") }
                ForEach(store.configuration.apps) { app in
                    Text(app.name).tag(app.id)
                }
            }
            .disabled(store.configuration.apps.isEmpty)

            List(selection: $selectedID) {
                ForEach(store.configuration.apps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                            Text(app.urlTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if app.id == store.configuration.defaultID {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("Default App")
                        }
                    }
                    .tag(app.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingApp = app }
                }
            }
            .border(Color.secondary.opacity(0.25))

            HStack {
                Menu("Add") {
                    ForEach(MarkdownExternalApp.presets) { app in
                        Button(app.name) { try? store.save(app) }
                            .disabled(store.configuration.apps.contains { $0.id == app.id })
                    }
                    Divider()
                    Button("Custom App…") {
                        editingApp = MarkdownExternalApp(
                            id: UUID().uuidString, name: "", urlTemplate: ""
                        )
                    }
                }
                .fixedSize()

                Button("Edit…") {
                    editingApp = store.configuration.apps.first { $0.id == selectedID }
                }
                .disabled(selectedID == nil)

                Button("Remove") {
                    if let selectedID { store.remove(id: selectedID) }
                    selectedID = nil
                }
                .disabled(selectedID == nil)

                Spacer()
            }

            Text("Obsidian opens files inside an existing vault.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 340)
        .sheet(item: $editingApp) { app in
            MarkdownExternalAppEditor(app: app, store: store)
        }
    }
}

private struct MarkdownExternalAppEditor: View {
    @State var app: MarkdownExternalApp
    @ObservedObject var store: MarkdownExternalApps
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var validationMessage: String? {
        do {
            try app.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("External App").font(.headline)
            TextField("Name", text: $app.name)

            TextField("URL Template", text: $app.urlTemplate)
                .font(.system(.body, design: .monospaced))
            Text("Use {path} for the absolute file path. Special characters are encoded automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = errorMessage ?? validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try store.save(app)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(validationMessage != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

}
