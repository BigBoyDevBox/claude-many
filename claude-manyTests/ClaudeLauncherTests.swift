import XCTest
@testable import claude_many

@MainActor
final class ClaudeLauncherTests: XCTestCase {
    func testStartPassesIsolatedDesktopAndCodePathsToTheProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-many-launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("Claude.app", isDirectory: true)
        let executable = bundle.appendingPathComponent("Contents/MacOS/Claude")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // A recording executable checks the real subprocess boundary without opening Claude.
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > "$0.arguments"
        printf '%s' "${CLAUDE_CONFIG_DIR-}" > "$0.code-config"
        printf '%s' "${CLAUDE_SECURESTORAGE_CONFIG_DIR-}" > "$0.secure-storage"
        printf '%s' "${CLAUDE_USER_DATA_DIR-}" > "$0.legacy-data"
        : > "$0.ready"
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let manager = ProfileManager(
            store: ProfileStore(fileURL: root.appendingPathComponent("profiles.json")),
            launcher: RealClaudeLauncher(),
            claudeBundleURL: bundle,
            dataRootDirectory: root.appendingPathComponent("Profiles With Spaces")
        )
        defer { manager.stopAll() }

        let profile = try manager.addProfile(named: "Work")
        try manager.start(id: profile.id)

        let ready = URL(fileURLWithPath: executable.path + ".ready")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path))

        let codeDirectory = profile.dataDirectory.appendingPathComponent(".claude", isDirectory: true)
        XCTAssertEqual(try output("arguments", executable: executable),
                       "--user-data-dir=\(profile.dataDirectory.path)\n")
        XCTAssertEqual(try output("code-config", executable: executable), codeDirectory.path)
        XCTAssertEqual(try output("secure-storage", executable: executable), codeDirectory.path)
        XCTAssertEqual(try output("legacy-data", executable: executable), "")
    }

    private func output(_ name: String, executable: URL) throws -> String {
        try String(contentsOfFile: executable.path + "." + name, encoding: .utf8)
    }
}
