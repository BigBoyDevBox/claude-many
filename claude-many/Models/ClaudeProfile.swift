import Foundation

/// A list entry for standard Claude or an isolated account. Only isolated entries are stored.
struct ClaudeProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var label: String
    let location: ClaudeInstanceLocation

    // Reserved v5 identity for the built-in entry; user-created profiles use random v4 IDs.
    private static let standardID = UUID(uuidString: "3C95B705-75C5-53EA-9A4D-1413412D918E")!
    static let standard = ClaudeProfile(id: standardID, label: "Default Claude", location: .standard)

    var isDefault: Bool { location == .standard }

    /// The standard path is display metadata, never a directory the manager creates or copies.
    var dataDirectory: URL {
        location.dataDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Claude", isDirectory: true)
    }

    init(id: UUID = UUID(), label: String, dataDirectory: URL) {
        self.id = id
        self.label = label
        location = .isolated(dataDirectory: dataDirectory)
    }

    private init(id: UUID, label: String, location: ClaudeInstanceLocation) {
        self.id = id
        self.label = label
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case dataDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        guard id != Self.standardID else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container,
                                                  debugDescription: "The default Claude entry cannot be stored as an isolated profile.")
        }
        label = try container.decode(String.self, forKey: .label)
        let path = try container.decode(String.self, forKey: .dataDirectory)
        location = .isolated(dataDirectory: URL(fileURLWithPath: path, isDirectory: true))
    }

    func encode(to encoder: Encoder) throws {
        guard !isDefault else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                        debugDescription: "The default Claude entry is built in and is not persisted."))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(dataDirectory.path, forKey: .dataDirectory)
    }
}
