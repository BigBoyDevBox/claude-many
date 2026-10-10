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
        XCTAssertTrue(FileManager.default.fileExists(atPath: codeDirectory.path))
    }

    func testDiscoveryAndStopIgnoreLegacyEnvironmentOnlyProcesses() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-many-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Use a native executable so the kernel reports its path, not a shell interpreter's.
        let source = root.appendingPathComponent("wait.c")
        let executable = root.appendingPathComponent("Claude")
        try Data("#include <unistd.h>\nint main(void) { alarm(30); for (;;) pause(); }\n".utf8).write(to: source)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = [source.path, "-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)

        let directory = root.appendingPathComponent("Work Account", isDirectory: true)
        let isolated = Process()
        isolated.executableURL = executable
        isolated.arguments = ["--user-data-dir=\(directory.path)"]
        isolated.environment = [:]
        let other = Process()
        other.executableURL = executable
        other.arguments = ["--user-data-dir=\(root.appendingPathComponent("Personal").path)"]
        other.environment = [:]
        let legacy = Process()
        legacy.executableURL = executable
        legacy.environment = ["CLAUDE_USER_DATA_DIR": directory.path]
        defer {
            for process in [isolated, other, legacy] where process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        try isolated.run()
        try other.run()
        try legacy.run()
        let handles = RealClaudeLauncher().runningHandles(executable: executable)
        XCTAssertEqual(Set(handles.map(\.processIdentifier)),
                       [isolated.processIdentifier, other.processIdentifier])
        let workHandle = try XCTUnwrap(handles.first { $0.processIdentifier == isolated.processIdentifier })
        XCTAssertEqual(workHandle.dataDirectory?.path, directory.path)

        workHandle.terminate()
        isolated.waitUntilExit()
        XCTAssertFalse(workHandle.isRunning)
        XCTAssertTrue(other.isRunning, "stopping an adopted profile must leave other profiles alive")
        XCTAssertTrue(legacy.isRunning, "legacy env-only instances must not be adopted or stopped")
    }

    private func output(_ name: String, executable: URL) throws -> String {
        try String(contentsOfFile: executable.path + "." + name, encoding: .utf8)
    }
}
