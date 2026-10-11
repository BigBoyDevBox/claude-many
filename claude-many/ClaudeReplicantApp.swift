import SwiftUI

@main
struct ClaudeReplicantApp: App {
    @State private var manager = ProfileManager()

    var body: some Scene {
        WindowGroup(AppBranding.name) {
            ContentView(manager: manager)
                .onAppear { manager.load() }
        }
        .defaultSize(width: 680, height: 500)

        Settings {
            SettingsView(manager: manager)
        }
    }
}
