import SwiftUI

struct ContentView: View {
    @Bindable var manager: ProfileManager
    @State private var showingAddAlert = false
    @State private var newProfileName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(manager.listedProfiles) { profile in
                    ProfileRowView(manager: manager, profile: profile)
                }

                if manager.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Isolated Profiles", systemImage: "person.2")
                    } description: {
                        Text("Default Claude uses your normal login.\nAdd isolated profiles to use other accounts alongside it.")
                    } actions: {
                        Button("Add Profile") {
                            newProfileName = ""
                            showingAddAlert = true
                        }
                    }
                }
            }
            .navigationTitle(AppBranding.name)
            .navigationSubtitle(AppBranding.subtitle)
            .toolbar {
                ToolbarItem {
                    Button {
                        newProfileName = ""
                        showingAddAlert = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .help("Add a profile for another Claude account")
                }
            }
            .alert("Add Profile", isPresented: $showingAddAlert) {
                TextField("Name (e.g. Work, Personal)", text: $newProfileName)
                Button("Add") { addProfile() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each profile gets its own private data directory.")
            }
        }
        .task { await manager.monitorRunningProcesses() }
        .alert(
            "Something went wrong",
            isPresented: errorBinding
        ) {
            Button("OK", role: .cancel) { manager.clearError() }
        } message: {
            Text(manager.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.clearError() } }
        )
    }

    private func addProfile() {
        do {
            try manager.addProfile(named: newProfileName)
        } catch {
            manager.report(error)
        }
    }
}
