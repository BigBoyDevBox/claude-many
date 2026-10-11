import Foundation

/// A standard launch leaves directory selection to Claude; isolated launches own their storage.
enum ClaudeInstanceLocation: Equatable, Hashable, Sendable {
    case standard
    case isolated(dataDirectory: URL)

    var dataDirectory: URL? {
        guard case .isolated(let directory) = self else { return nil }
        return directory
    }
}
