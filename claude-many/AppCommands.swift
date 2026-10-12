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

/// Single-window app, so the command context is effectively app-global:
/// the view pushes the current selection state here and menu commands read
/// it. `@FocusedValue` stays the primary lookup (correct if the app ever
/// grows a second window); this is the deterministic fallback — an
/// ObservableObject because Commands rebuilds track DynamicProperty
/// dependencies, not Observation-framework reads.
@MainActor
final class ProfileCommandCenter: ObservableObject {
    static let shared = ProfileCommandCenter()
    @Published var context = ProfileCommandContext()
}

struct ProfileCommands: Commands {
    @FocusedValue(\.profileCommands) private var focusedContext
    @ObservedObject private var center = ProfileCommandCenter.shared

    private var context: ProfileCommandContext {
        focusedContext ?? center.context
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Profile") { context.newProfile() }
                .keyboardShortcut("n")
        }

        CommandMenu("Profiles") {
            Button(context.openTitle) { context.openSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!context.canOpen)
            Button(context.stopTitle) { context.stopSelected() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!context.canStop)
            Button("Rename…") { context.renameSelected() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!context.canRename)
            Button(context.deleteTitle) { context.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!context.canDelete)

            Divider()

            Button("Reveal in Finder") { context.revealSelected() }
                .disabled(!context.canReveal)
            Button("Copy Data Folder Path") { context.copyPathSelected() }
                .disabled(!context.canCopyPath)

            Divider()

            Button("Start All") { context.startAll() }
                .disabled(!context.canStartAll)
            Button("Stop All") { context.stopAll() }
                .disabled(!context.canStopAll)

            Divider()

            Button("Open Profiles Folder in Finder") { context.openProfilesFolder() }
        }

        CommandGroup(replacing: .help) {
            Button("Claude Replicant Help") {
                NSWorkspace.shared.open(AppBranding.helpURL)
            }
        }
    }
}
