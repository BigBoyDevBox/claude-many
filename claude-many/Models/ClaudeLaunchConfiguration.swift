import Foundation

/// Select normal Claude locations or keep isolated Desktop and Code state together.
struct ClaudeLaunchConfiguration {
    let location: ClaudeInstanceLocation

    private static let userDataArguments = ["--user-data-dir", "-user-data-dir"]
    private static let legacyUserDataEnvironment = "CLAUDE_USER_DATA_DIR"
    private static let codeConfigEnvironment = "CLAUDE_CONFIG_DIR"
    private static let secureStorageEnvironment = "CLAUDE_SECURESTORAGE_CONFIG_DIR"

    init(dataDirectory: URL) {
        location = .isolated(dataDirectory: dataDirectory)
    }

    init(location: ClaudeInstanceLocation) {
        self.location = location
    }

    var codeConfigurationDirectory: URL? {
        location.dataDirectory?.appendingPathComponent(".claude", isDirectory: true)
    }

    var arguments: [String] {
        guard let directory = location.dataDirectory else { return [] }
        return ["\(Self.userDataArguments[0])=\(directory.path)"]
    }

    func environment(inheriting inherited: [String: String]) -> [String: String] {
        var environment = inherited
        environment.removeValue(forKey: Self.legacyUserDataEnvironment)
        environment.removeValue(forKey: Self.codeConfigEnvironment)
        environment.removeValue(forKey: Self.secureStorageEnvironment)
        if let directory = codeConfigurationDirectory {
            environment[Self.codeConfigEnvironment] = directory.path
            environment[Self.secureStorageEnvironment] = directory.path
        }
        return environment
    }

    static func dataDirectory(in arguments: [String]) -> URL? {
        location(in: arguments)?.dataDirectory
    }

    static func location(in arguments: [String]) -> ClaudeInstanceLocation? {
        var path: String?

        // Chromium requires '='; a following argv entry is not a switch value.
        for argument in arguments {
            if argument == "--" { break }

            if userDataArguments.contains(argument) {
                path = ""
                continue
            }

            guard let name = userDataArguments.first(where: { argument.hasPrefix($0 + "=") }) else { continue }
            let prefix = name + "="
            path = String(argument.dropFirst(prefix.count))
        }

        guard let path else { return .standard }
        guard path.hasPrefix("/") else { return nil }
        return .isolated(dataDirectory: URL(fileURLWithPath: path, isDirectory: true))
    }
}
