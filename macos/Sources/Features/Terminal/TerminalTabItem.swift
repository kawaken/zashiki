import AppKit
import SwiftUI

/// Actions always carry the tab that was clicked, including background tabs.
enum TerminalTabAction {
    case rename
    case setTitle(String)
    case setColor(TerminalTabColor)
    case finishEditing
    case closeOthers
    case closeRight
}

/// AppKit owns pointer tracking and the field editor so tab dragging, double
/// clicks, right clicks, and the window's drag region do not compete.
struct TerminalTabItem: NSViewRepresentable {
    @ObservedObject var tab: TerminalTab
    let isSelected: Bool
    let shortcut: String?
    let showsBellInTitle: Bool
    let canCloseOthers: Bool
    let canCloseRight: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onAction: (TerminalTabAction) -> Void
    let onMove: (UUID, Bool) -> Void

    func makeNSView(context: Context) -> TerminalTabItemView {
        TerminalTabItemView()
    }

    func updateNSView(_ view: TerminalTabItemView, context: Context) {
        view.item = self
        view.refresh()
    }
}

final class TerminalTabItemView: NSView, NSTextFieldDelegate, NSDraggingSource {
    private static let pasteboardType = NSPasteboard.PasteboardType("dev.kawaken.zashiki.terminal-tab")
    var item: TerminalTabItem?
    private let titleField = NSTextField(labelWithString: "")
    private let shortcutField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private var isHovering = false
    private var isEditing = false
    private var insertionAfter: Bool?
    private var resignObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center
        titleField.delegate = self
        shortcutField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        shortcutField.textColor = .secondaryLabelColor
        shortcutField.alignment = .right
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        closeButton.toolTip = "Close Tab"
        closeButton.setAccessibilityLabel("Close Tab")
        [titleField, shortcutField, closeButton].forEach { addSubview($0) }
        registerForDraggedTypes([Self.pasteboardType])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.finishEditing(commit: true, restoreFocus: false) }
        }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func refresh() {
        guard let item else { return }
        if isEditing && !item.tab.isEditingTitle {
            finishEditing(commit: true, restoreFocus: false)
            return
        }
        if !isEditing {
            titleField.stringValue = item.tab.bell && item.showsBellInTitle ? "🔔 \(item.tab.title)" : item.tab.title
        }
        let fontName = item.tab.focusedSurface?.derivedConfig.windowTitleFontFamily
        titleField.font = fontName.flatMap { NSFont(name: $0, size: NSFont.systemFontSize) }
            ?? .systemFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = item.isSelected ? .labelColor : .secondaryLabelColor
        shortcutField.stringValue = item.shortcut ?? ""
        closeButton.isHidden = !isHovering || isEditing
        setAccessibilityLabel(item.tab.title)
        setAccessibilityValue(item.isSelected ? "Selected" : "")
        needsLayout = true
        needsDisplay = true
        if item.tab.isEditingTitle && !isEditing {
            DispatchQueue.main.async { [weak self] in self?.beginEditing() }
        }
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16)
        shortcutField.frame = NSRect(x: max(24, bounds.width - 36), y: (bounds.height - 16) / 2, width: 28, height: 16)
        let colorInset: CGFloat = item?.tab.color == .none ? 0 : 14
        titleField.frame = NSRect(x: 26 + colorInset, y: (bounds.height - 20) / 2,
                                 width: max(0, bounds.width - 66 - colorInset), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let item else { return }
        if !item.isSelected {
            NSColor.labelColor.withAlphaComponent(isHovering ? 0.04 : 0.08).setFill()
            bounds.fill()
        }
        if let color = item.tab.color.displayColor {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 28, y: (bounds.height - 8) / 2, width: 8, height: 8)).fill()
        }
        if let insertionAfter {
            NSColor.controlAccentColor.setFill()
            NSRect(x: insertionAfter ? bounds.width - 2 : 0, y: 0, width: 2, height: bounds.height).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { isHovering = false; refresh() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if isEditing || hit === closeButton { return hit }
        return self
    }

    override func accessibilityPerformPress() -> Bool { item?.onSelect(); return true }
    @objc private func closeTab() { item?.onClose() }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 { item?.onAction(.rename) }
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        item?.onSelect()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isEditing, let original = mouseDownEvent, let item,
              hypot(event.locationInWindow.x - original.locationInWindow.x,
                    event.locationInWindow.y - original.locationInWindow.y) > 4 else { return }
        mouseDownEvent = nil
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(item.tab.id.uuidString, forType: Self.pasteboardType)
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        drag.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [drag], event: original, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    private func draggedTab(_ sender: NSDraggingInfo) -> UUID? {
        guard let source = sender.draggingSource as? TerminalTabItemView,
              source.window === window,
              let value = sender.draggingPasteboard.string(forType: Self.pasteboardType),
              let id = UUID(uuidString: value), id != item?.tab.id else { return nil }
        return id
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTab(sender) != nil else { return [] }
        insertionAfter = convert(sender.draggingLocation, from: nil).x > bounds.midX
        needsDisplay = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { clearInsertion() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearInsertion() }
    private func clearInsertion() { insertionAfter = nil; needsDisplay = true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearInsertion() }
        guard let id = draggedTab(sender) else { return false }
        item?.onMove(id, convert(sender.draggingLocation, from: nil).x > bounds.midX)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(TabMenuItem("Rename Tab…") { item.onAction(.rename) })
        let palette = NSMenuItem()
        let hosting = NSHostingView(rootView: TabColorMenuView(selectedColor: item.tab.color) { [weak menu] color in
            item.onAction(.setColor(color))
            menu?.cancelTracking()
        })
        hosting.frame.size = hosting.intrinsicContentSize
        palette.view = hosting
        menu.addItem(palette)
        menu.addItem(.separator())
        menu.addItem(TabMenuItem("Close Tab", action: item.onClose))
        let others = TabMenuItem("Close Other Tabs") { item.onAction(.closeOthers) }
        others.isEnabled = item.canCloseOthers
        menu.addItem(others)
        let right = TabMenuItem("Close Tabs to the Right") { item.onAction(.closeRight) }
        right.isEnabled = item.canCloseRight
        menu.addItem(right)
        return menu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditing, let editor = titleField.currentEditor() as? NSTextView,
              window?.firstResponder === editor,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": editor.pasteAsPlainText(nil)
        case "c": editor.copy(nil)
        case "x": editor.cut(nil)
        case "a": editor.selectAll(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func beginEditing() {
        guard !isEditing, let item, item.tab.isEditingTitle, window != nil else { return }
        isEditing = true
        titleField.stringValue = item.tab.titleOverride ?? item.tab.title
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBezeled = true
        titleField.drawsBackground = true
        closeButton.isHidden = true
        titleField.selectText(nil)
    }

    private func finishEditing(commit: Bool, restoreFocus: Bool) {
        guard isEditing, let item else { return }
        isEditing = false
        let title = titleField.currentEditor()?.string ?? titleField.stringValue
        item.tab.isEditingTitle = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBezeled = false
        titleField.drawsBackground = false
        if commit { item.onAction(.setTitle(title)) }
        if restoreFocus { item.onAction(.finishEditing) }
        refresh()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishEditing(commit: true, restoreFocus: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishEditing(commit: false, restoreFocus: true)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(commit: true, restoreFocus: true)
            return true
        }
        return false
    }
}

private final class TabMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

/// The space after the tabs retains standard window movement.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
