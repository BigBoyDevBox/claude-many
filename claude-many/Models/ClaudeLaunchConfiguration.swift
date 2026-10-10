import Foundation

/// Keep Desktop storage and Claude Code state together without sharing the default profile.
struct ClaudeLaunchConfiguration {
    let dataDirectory: URL

    private static let userDataArgument = "--user-data-dir"
    private static let legacyUserDataEnvironment = "CLAUDE_USER_DATA_DIR"
    private static let codeConfigEnvironment = "CLAUDE_CONFIG_DIR"
    private static let secureStorageEnvironment = "CLAUDE_SECURESTORAGE_CONFIG_DIR"

    var codeConfigurationDirectory: URL {
        dataDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    var arguments: [String] {
        ["\(Self.userDataArgument)=\(dataDirectory.path)"]
    }

    func environment(inheriting inherited: [String: String]) -> [String: String] {
        var environment = inherited
        environment.removeValue(forKey: Self.legacyUserDataEnvironment)
        environment[Self.codeConfigEnvironment] = codeConfigurationDirectory.path
        environment[Self.secureStorageEnvironment] = codeConfigurationDirectory.path
        return environment
    }

    static func dataDirectory(in arguments: [String]) -> URL? {
        let prefix = userDataArgument + "="
        var path: String?

        // Chromium requires '='; a following argv entry is not a switch value.
        for argument in arguments {
            if argument == "--" { break }

            if argument == userDataArgument {
                path = ""
                continue
            }

            guard argument.hasPrefix(prefix) else { continue }
            path = String(argument.dropFirst(prefix.count))
        }

        guard let path, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
