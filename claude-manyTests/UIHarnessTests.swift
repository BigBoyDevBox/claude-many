import XCTest
import AppKit

/// SCRATCH-BRANCH ONLY — visual/interaction harness, never merged.
/// Runs inside the real app process (hosted test): dumps the menu bar with
/// live enablement, captures real windows to PNG (frame view, so titlebar +
/// toolbar included), and drives the UI with synthesized NSEvents through
/// NSApp.sendEvent plus performActionForItem for real menu dispatch.
@MainActor
final class UIHarnessTests: XCTestCase {
    private var outDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ui-harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var phase: String {
        (try? String(contentsOfFile: "/tmp/harness-phase", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "full"
    }

    private func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[harness] \(message)\n".utf8))
    }

    func testHarness() async throws {
        guard let app = NSApp else {
            XCTFail("no running application")
            return
        }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        try await waitForWindow(named: "Claude Replicant")
        try await Task.sleep(for: .milliseconds(800))
        mainWindow()?.makeKeyAndOrderFront(nil)
        app.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(400))
        log("key window: \(NSApp.keyWindow?.title ?? "none")")

        if phase == "missing" {
            dumpMenus(prefix: "missing")
            try captureWindows(prefix: "90-missing-bundle")
            return
        }

        dumpMenus(prefix: "a-idle")
        try captureWindows(prefix: "01-idle")

        // Cmd-N: New Profile via its real key equivalent.
        sendKey(keyCode: 45, chars: "n", mods: .command)
        try await Task.sleep(for: .milliseconds(700))
        try captureWindows(prefix: "02-after-new-profile")
        log("first responder after Cmd-N: \(firstResponderDescription())")

        // The new row is in inline-rename mode; type a name, Return commits.
        typeText("Harness Profile")
        sendKey(keyCode: 36, chars: "\r")
        try await Task.sleep(for: .milliseconds(400))
        try captureWindows(prefix: "03-after-rename")

        // Cmd-Return: open the selected profile (launches the fake Claude.app).
        sendKey(keyCode: 36, chars: "\r", mods: .command)
        try await Task.sleep(for: .milliseconds(1500))
        try captureWindows(prefix: "04-after-open")
        dumpMenus(prefix: "b-running")

        // Shift-Cmd-Return: stop it.
        sendKey(keyCode: 36, chars: "\r", mods: [.command, .shift])
        try await Task.sleep(for: .milliseconds(600))
        try captureWindows(prefix: "05-after-stop")

        // Cmd-Z twice: undo rename, then undo creation.
        sendKey(keyCode: 6, chars: "z", mods: .command)
        try await Task.sleep(for: .milliseconds(300))
        sendKey(keyCode: 6, chars: "z", mods: .command)
        try await Task.sleep(for: .milliseconds(400))
        try captureWindows(prefix: "06-after-undo")

        // Real menu dispatch: Start All via performActionForItem.
        invokeMenuItem("Start All", inMenuTitled: "Profiles")
        try await Task.sleep(for: .milliseconds(1500))
        try captureWindows(prefix: "07-after-start-all")
        dumpMenus(prefix: "c-all-running")

        invokeMenuItem("Stop All", inMenuTitled: "Profiles")
        try await Task.sleep(for: .milliseconds(600))
        try captureWindows(prefix: "08-after-stop-all")

        // Cmd-,: Settings window; capture; Cmd-W closes it.
        sendKey(keyCode: 43, chars: ",", mods: .command)
        try await Task.sleep(for: .milliseconds(900))
        try captureWindows(prefix: "09-settings")

        sendKey(keyCode: 13, chars: "w", mods: .command)
        try await Task.sleep(for: .milliseconds(400))
        try captureWindows(prefix: "10-back-to-main")

        writeReport()
        log("done; artifacts in \(outDir.path)")
    }

    // MARK: - Synthesized input

    /// Feeds a key event into the app's normal dispatch: window first,
    /// then menu key equivalents — exactly like a physical keypress.
    private func sendKey(keyCode: UInt16, chars: String, mods: NSEvent.ModifierFlags = []) {
        guard let window = NSApp.keyWindow ?? mainWindow() else {
            log("sendKey: no window")
            return
        }
        for type: NSEvent.EventType in [.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: mods,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: chars,
                charactersIgnoringModifiers: chars.lowercased(),
                isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.sendEvent(event)
        }
    }

    /// Sends each character through the field editor, like real typing.
    private func typeText(_ text: String) {
        for character in text {
            NSApp.sendAction(#selector(NSText.insertText(_:)), to: nil, from: String(character) as NSString)
        }
    }

    private func firstResponderDescription() -> String {
        NSApp.keyWindow.map { String(describing: $0.firstResponder) } ?? "no key window"
    }

    // MARK: - Menus

    private func dumpMenus(prefix: String) {
        var lines: [String] = []
        func walk(_ menu: NSMenu, depth: Int) {
            menu.update()
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
        try? text.write(to: outDir.appendingPathComponent("menus-\(prefix).txt"),
                        atomically: true, encoding: .utf8)
        log("menu dump (\(prefix)):\n\(text)")
    }

    private func describe(key: String, mask: NSEvent.ModifierFlags) -> String {
        var mods = ""
        if mask.contains(.control) { mods += "⌃" }
        if mask.contains(.option) { mods += "⌥" }
        if mask.contains(.shift) { mods += "⇧" }
        if mask.contains(.command) { mods += "⌘" }
        return mods + key.uppercased()
    }

    /// Simulates choosing a menu item: the same dispatch a real click uses.
    private func invokeMenuItem(_ title: String, inMenuTitled menuTitle: String) {
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.title == title { return item }
                if let found = item.submenu.flatMap(search) { return found }
            }
            return nil
        }
        guard let menu = NSApp.mainMenu, let item = search(menu) else {
            log("menu item '\(title)' not found")
            return
        }
        guard let owner = item.menu else { return }
        owner.update()
        log("invoke '\(item.title)' enabled=\(item.isEnabled)")
        _ = owner.performActionForItem(at: owner.index(of: item))
    }

    // MARK: - Windows

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

    /// Captures the whole window — the frame view includes titlebar and toolbar.
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

    private func writeReport() {
        let report = NSApp.windows.map {
            "\($0.windowNumber): '\($0.title)' visible=\($0.isVisible) key=\($0.isKeyWindow) type=\(type(of: $0)) firstResponder=\(String(describing: $0.firstResponder))"
        }
        try? report.joined(separator: "\n").write(
            to: outDir.appendingPathComponent("windows.txt"), atomically: true, encoding: .utf8)
    }
}
