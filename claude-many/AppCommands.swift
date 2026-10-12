import SwiftUI
import AppKit

/// The focused window's profile actions, exposed to the menu bar. Menus read
/// the precomputed titles and enabled flags; the closures act on the window's
/// current selection. Value type rebuilt by the view on every state change.
struct ProfileCommandContext {
    // State for labels and enablement
    var selectionCount: Int = 0
    var canOpen: Bool = false
    var canStop: Bool = false
    var canRename: Bool = false
    var canReveal: Bool = false
    var canCopyPath: Bool = false
    var canDelete: Bool = false
    var canStartAll: Bool = false
    var canStopAll: Bool = false
    var openTitle: String = "Open"
    var stopTitle: String = "Stop"
    var deleteTitle: String = "Delete Profile…"

    // Actions (empty selection keeps them harmless)
    var newProfile: () -> Void = {}
    var openSelected: () -> Void = {}
    var stopSelected: () -> Void = {}
    var renameSelected: () -> Void = {}
    var deleteSelected: () -> Void = {}
    var revealSelected: () -> Void = {}
    var copyPathSelected: () -> Void = {}
    var startAll: () -> Void = {}
    var stopAll: () -> Void = {}
    var openProfilesFolder: () -> Void = {}
}

struct ProfileCommandContextKey: FocusedValueKey {
    typealias Value = ProfileCommandContext
}

extension FocusedValues {
    var profileCommands: ProfileCommandContext? {
        get { self[ProfileCommandContextKey.self] }
        set { self[ProfileCommandContextKey.self] = newValue }
    }
}

struct ProfileCommands: Commands {
    @FocusedValue(\.profileCommands) private var context

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Profile") { context?.newProfile() }
                .keyboardShortcut("n")
        }

        CommandMenu("Profiles") {
            Button(context?.openTitle ?? "Open") { context?.openSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(context?.canOpen != true)
            Button(context?.stopTitle ?? "Stop") { context?.stopSelected() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(context?.canStop != true)
            Button("Rename…") { context?.renameSelected() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(context?.canRename != true)
            Button(context?.deleteTitle ?? "Delete Profile…") { context?.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(context?.canDelete != true)

            Divider()

            Button("Reveal in Finder") { context?.revealSelected() }
                .disabled(context?.canReveal != true)
            Button("Copy Data Folder Path") { context?.copyPathSelected() }
                .disabled(context?.canCopyPath != true)

            Divider()

            Button("Start All") { context?.startAll() }
                .disabled(context?.canStartAll != true)
            Button("Stop All") { context?.stopAll() }
                .disabled(context?.canStopAll != true)

            Divider()

            Button("Open Profiles Folder in Finder") { context?.openProfilesFolder() }
        }

        CommandGroup(replacing: .help) {
            Button("Claude Replicant Help") {
                NSWorkspace.shared.open(AppBranding.helpURL)
            }
        }
    }
}
