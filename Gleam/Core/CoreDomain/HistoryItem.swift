import Foundation

struct HistoryItem: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let createdAt: Date
    let result: ScanResult
    let contextTags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case result
        case contextTags
    }

    init(id: String, createdAt: Date, result: ScanResult, contextTags: [String]) {
        self.id = id
        self.createdAt = createdAt
        self.result = result
        self.contextTags = contextTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        result = try container.decode(ScanResult.self, forKey: .result)
        contextTags = try container.decodeIfPresent([String].self, forKey: .contextTags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(result, forKey: .result)
        if !contextTags.isEmpty {
            try container.encode(contextTags, forKey: .contextTags)
        }
    }
}
