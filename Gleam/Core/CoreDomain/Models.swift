import Foundation

struct ScanResult: Codable, Equatable, Hashable {
    let whitenessScore: Int
    let shade: String
    let detectedIssues: [DetectedIssue]
    let confidence: Double
    let recommendations: Recommendations
    let referralNeeded: Bool
    let disclaimer: String
    let planSummary: String
}

struct DetectedIssue: Codable, Equatable, Hashable {
    let key: String
    let severity: String
    let notes: String
}

struct Recommendations: Codable, Equatable, Hashable {
    let immediate: [String]
    let daily: [String]
    let weekly: [String]
    let caution: [String]
}

enum AppError: Error, LocalizedError, Equatable {
    case network
    case decoding
    case invalidImage
    case unauthorized
    case unknown

    var errorDescription: String? {
        switch self {
        case .network: return "Network error"
        case .decoding: return "Decoding error"
        case .invalidImage: return "Invalid image"
        case .unauthorized: return "Unauthorized"
        case .unknown: return "Unknown error"
        }
    }
}


