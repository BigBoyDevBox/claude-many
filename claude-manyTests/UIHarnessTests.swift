import XCTest
import AppKit

/// SCRATCH-BRANCH ONLY — visual/interaction harness, never merged.
/// Runs inside the real app process (hosted test): dumps the menu bar,
/// captures real windows to PNG (frame view, so titlebar + toolbar included),
/// and drives the UI through the responder chain (sendAction on menu items,
/// insertText/insertNewline for typing). No accessibility permissions needed.
@MainActor
final class UIHarnessTests: XCTestCase {
    private var outDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ui-harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[harness] \(message)\n".utf8))
    }

    func testHarness() async throws {
        guard let app = NSApp else {
            XCTFail("no running application")
            return
        }
        app.activate()
        try await waitForWindow(named: "Claude Replicant")
        try await Task.sleep(for: .milliseconds(800))
        let window = mainWindow()

        dumpMenus()
        try captureWindows(prefix: "01-idle")

        // File > New Profile via the actual menu item.
        let newItem = findMenuItem { $0.title == "New Profile" }
        invokeMenuItem(newItem)
        try await Task.sleep(for: .milliseconds(700))
        try captureWindows(prefix: "02-after-new-profile")

        // The new row should be in inline-rename mode; type a name, Return commits.
        typeText("Harness Profile")
        sendAction(#selector(NSText.insertNewline(_:)))
        try await Task.sleep(for: .milliseconds(400))
        try captureWindows(prefix: "03-after-rename")

        // Start the new profile via its row button (fake Claude.app installed by CI).
        let started = clickButton(titled: "Start", in: window, lastMatch: true)
        log("clicked row Start: \(started)")
        try await Task.sleep(for: .milliseconds(1500))
        try captureWindows(prefix: "04-after-start")

        // Stop it again via the Stop button.
        let stopped = clickButton(titled: "Stop", in: window, lastMatch: true)
        log("clicked row Stop: \(stopped)")
        try await Task.sleep(for: .milliseconds(500))
        try captureWindows(prefix: "05-after-stop")

        // Edit > Undo: undoes the profile creation.
        let undoItem = findMenuItem { $0.action.map { NSStringFromSelector($0) == "undo:" } ?? false }
        invokeMenuItem(undoItem)
        try await Task.sleep(for: .milliseconds(400))
        try captureWindows(prefix: "06-after-undo")

        // Settings via the Settings scene's selector (what Cmd-, sends).
        sendAction(NSSelectorFromString("showSettingsWindow:"))
        try await Task.sleep(for: .milliseconds(500))
        sendAction(NSSelectorFromString("showPreferencesWindow:"))
        try await Task.sleep(for: .milliseconds(900))
        try captureWindows(prefix: "07-settings")

        writeReport()
        log("done; artifacts in \(outDir.path)")
    }

    // MARK: - Menus

    private func dumpMenus() {
        var lines: [String] = []
        func walk(_ menu: NSMenu, depth: Int) {
            for item in menu.items {
                let pad = String(repeating: "  ", count: depth)
                if item.isSeparatorItem {
                    lines.append("\(pad)---")
                    continue
                }
                let key = item.keyEquivalent.isEmpty
                    ? ""
                    : " [\(describe(key: item.keyEquivalent, mask: item.keyEquivalentModifierMask))]"
                let action = item.action.map(NSStringFromSelector) ?? "-"
                lines.append("\(pad)\(item.title)\(key) enabled=\(item.isEnabled) action=\(action)")
                if let sub = item.submenu { walk(sub, depth: depth + 1) }
            }
        }
        if let main = NSApp.mainMenu { walk(main, depth: 0) }
        let text = lines.joined(separator: "\n")
        try? text.write(to: outDir.appendingPathComponent("menus.txt"), atomically: true, encoding: .utf8)
        log("menu dump:\n\(text)")
    }

    private func describe(key: String, mask: NSEvent.ModifierFlags) -> String {
        var mods = ""
        if mask.contains(.control) { mods += "⌃" }
        if mask.contains(.option) { mods += "⌥" }
        if mask.contains(.shift) { mods += "⇧" }
        if mask.contains(.command) { mods += "⌘" }
        return mods + key.uppercased()
    }

    private func findMenuItem(matching predicate: (NSMenuItem) -> Bool) -> NSMenuItem? {
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if predicate(item) { return item }
                if let found = item.submenu.flatMap(search) { return found }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }

    private func invokeMenuItem(_ item: NSMenuItem?) {
        guard let item else {
            log("invokeMenuItem: item not found")
            return
        }
        log("invoking menu item '\(item.title)' action=\(item.action.map(NSStringFromSelector) ?? "nil")")
        if let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        } else if let menu = item.menu {
            _ = menu.performActionForItem(at: menu.index(of: item))
        }
    }

    // MARK: - Responder chain input

    /// Sends each character through the field editor, like real typing.
    private func typeText(_ text: String) {
        for character in text {
            NSApp.sendAction(#selector(NSText.insertText(_:)), to: nil, from: String(character) as NSString)
        }
    }

    private func sendAction(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    // MARK: - Windows / views

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "Claude Replicant" }
            ?? NSApp.windows.first { !($0 is NSPanel) }
    }

    private func waitForWindow(named title: String) async throws {
        for _ in 0..<100 {
            if NSApp.windows.contains(where: { $0.title == title }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        log("warning: window '\(title)' not found; windows=\(NSApp.windows.map(\.title))")
    }

    private func captureWindows(prefix: String) throws {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            let safeTitle = window.title.isEmpty ? "untitled" : window.title
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "-")
            try capture(window: window, file: "\(prefix)-win\(index)-\(safeTitle).png")
        }
    }

    /// Captures the whole window — frame view includes titlebar and toolbar.
    private func capture(window: NSWindow, file: String) throws {
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        guard let root = window.contentView?.superview ?? window.contentView,
              root.bounds.width > 0, root.bounds.height > 0 else { return }
        let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: outDir.appendingPathComponent(file))
        log("captured \(file) \(Int(root.bounds.width))x\(Int(root.bounds.height))")
    }

    private func clickButton(titled title: String, in window: NSWindow?, lastMatch: Bool) -> Bool {
        guard let content = window?.contentView else { return false }
        var matches: [NSButton] = []
        func collect(_ view: NSView) {
            if let button = view as? NSButton,
               button.title == title, button.isEnabled, !button.isHidden {
                matches.append(button)
            }
            view.subviews.forEach(collect)
        }
        collect(content)
        guard let button = lastMatch ? matches.last : matches.first else { return false }
        button.performClick(nil)
        return true
    }

    private func writeReport() {
        let report = NSApp.windows.map {
            "\($0.windowNumber): '\($0.title)' visible=\($0.isVisible) type=\(type(of: $0)) firstResponder=\(String(describing: $0.firstResponder))"
        }
        try? report.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("windows.txt"), atomically: true, encoding: .utf8)
    }
}
