import Foundation

struct HistoryItem: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let createdAt: Date
    var result: ScanResult
    let contextTags: [String]
    var isLocalOnly: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case result
        case contextTags
        case isLocalOnly
    }

    init(id: String, createdAt: Date, result: ScanResult, contextTags: [String], isLocalOnly: Bool = false) {
        self.id = id
        self.createdAt = createdAt
        self.result = result
        self.contextTags = contextTags
        self.isLocalOnly = isLocalOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        result = try container.decode(ScanResult.self, forKey: .result)
        contextTags = try container.decodeIfPresent([String].self, forKey: .contextTags) ?? []
        isLocalOnly = try container.decodeIfPresent(Bool.self, forKey: .isLocalOnly) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(result, forKey: .result)
        if !contextTags.isEmpty {
            try container.encode(contextTags, forKey: .contextTags)
        }
        try container.encode(isLocalOnly, forKey: .isLocalOnly)
    }
}
