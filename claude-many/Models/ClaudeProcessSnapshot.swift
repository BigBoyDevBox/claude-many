import Foundation

/// Decode macOS KERN_PROCARGS2 without trusting incomplete argument lists.
struct ClaudeProcessSnapshot {
    let executablePath: String
    let arguments: [String]
    let hasLegacyDataDirectoryOverride: Bool

    private static let legacyOverridePrefix = Array("CLAUDE_USER_DATA_DIR=".utf8)

    init?(buffer: [UInt8]) {
        let headerSize = MemoryLayout<Int32>.size
        guard buffer.count >= headerSize else { return nil }

        let argumentCount = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argumentCount > 0, argumentCount <= buffer.count - headerSize else { return nil }

        var index = headerSize
        guard let executableEnd = buffer[index...].firstIndex(of: 0), executableEnd > index,
              let executablePath = String(bytes: buffer[index..<executableEnd], encoding: .utf8) else {
            return nil
        }

        // The kernel pads between the executable path and argv[0]. Empty later args are retained.
        index = executableEnd + 1
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        for _ in 0..<argumentCount {
            guard index < buffer.count, let end = buffer[index...].firstIndex(of: 0),
                  let argument = String(bytes: buffer[index..<end], encoding: .utf8) else {
                return nil
            }
            arguments.append(argument)
            index = end + 1
        }

        self.executablePath = executablePath
        self.arguments = arguments
        // A legacy environment hint may belong to an older app that relocates storage.
        // It cannot identify a safe default instance, even when no directory switch exists.
        hasLegacyDataDirectoryOverride = buffer[index...].split(separator: 0).contains {
            $0.starts(with: Self.legacyOverridePrefix) && $0.count > Self.legacyOverridePrefix.count
        }
    }
}
