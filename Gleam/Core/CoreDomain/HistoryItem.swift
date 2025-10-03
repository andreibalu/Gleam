import Foundation

struct HistoryItem: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let createdAt: Date
    let result: ScanResult
}
