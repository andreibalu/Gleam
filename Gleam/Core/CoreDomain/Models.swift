import Foundation

struct ScanResult: Codable, Equatable, Hashable {
    let whitenessScore: Int
    let shade: String
    let detectedIssues: [DetectedIssue]
    let confidence: Double
    let referralNeeded: Bool
    let disclaimer: String
    let personalTakeaway: String

    private enum CodingKeys: String, CodingKey {
        case whitenessScore
        case shade
        case detectedIssues
        case confidence
        case referralNeeded
        case disclaimer
        case personalTakeaway
        case legacyPlanSummary = "planSummary"
    }

    init(
        whitenessScore: Int,
        shade: String,
        detectedIssues: [DetectedIssue],
        confidence: Double,
        referralNeeded: Bool,
        disclaimer: String,
        personalTakeaway: String
    ) {
        self.whitenessScore = whitenessScore
        self.shade = shade
        self.detectedIssues = detectedIssues
        self.confidence = confidence
        self.referralNeeded = referralNeeded
        self.disclaimer = disclaimer
        self.personalTakeaway = personalTakeaway
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whitenessScore = try container.decode(Int.self, forKey: .whitenessScore)
        shade = try container.decode(String.self, forKey: .shade)
        detectedIssues = try container.decodeIfPresent([DetectedIssue].self, forKey: .detectedIssues) ?? []
        confidence = try container.decode(Double.self, forKey: .confidence)
        referralNeeded = try container.decodeIfPresent(Bool.self, forKey: .referralNeeded) ?? false
        disclaimer = try container.decodeIfPresent(String.self, forKey: .disclaimer) ?? ""
        personalTakeaway = try container.decodeIfPresent(String.self, forKey: .personalTakeaway)
            ?? container.decodeIfPresent(String.self, forKey: .legacyPlanSummary)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(whitenessScore, forKey: .whitenessScore)
        try container.encode(shade, forKey: .shade)
        try container.encode(detectedIssues, forKey: .detectedIssues)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(referralNeeded, forKey: .referralNeeded)
        try container.encode(disclaimer, forKey: .disclaimer)
        try container.encode(personalTakeaway, forKey: .personalTakeaway)
    }
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

enum PlanSource: String, Equatable {
    case `default`
    case latestCache = "latest-cache"
    case openai
}

enum PlanStatusReason: String, Equatable {
    case missingHistory = "missing-history"
    case historyIdentical = "history-identical"
    case latestRequest = "latest-request"
    case insufficientScans = "insufficient-scans"
    case awaitingRefresh = "awaiting-refresh"
}

struct PlanStatus: Equatable {
    let source: PlanSource
    let isUnchanged: Bool
    let reason: PlanStatusReason?
    let inputHash: String?
    let updatedAt: Date?
    let totalScans: Int?
    let scansUntilNextPlan: Int?
    let scansSinceLastPlan: Int?
    let latestPlanScanCount: Int?
    let planAvailable: Bool?
    let nextPlanAtScanCount: Int?
    let refreshInterval: Int?

    init(
        source: PlanSource,
        isUnchanged: Bool,
        reason: PlanStatusReason?,
        inputHash: String?,
        updatedAt: Date?,
        totalScans: Int? = nil,
        scansUntilNextPlan: Int? = nil,
        scansSinceLastPlan: Int? = nil,
        latestPlanScanCount: Int? = nil,
        planAvailable: Bool? = nil,
        nextPlanAtScanCount: Int? = nil,
        refreshInterval: Int? = nil
    ) {
        self.source = source
        self.isUnchanged = isUnchanged
        self.reason = reason
        self.inputHash = inputHash
        self.updatedAt = updatedAt
        self.totalScans = totalScans
        self.scansUntilNextPlan = scansUntilNextPlan
        self.scansSinceLastPlan = scansSinceLastPlan
        self.latestPlanScanCount = latestPlanScanCount
        self.planAvailable = planAvailable
        self.nextPlanAtScanCount = nextPlanAtScanCount
        self.refreshInterval = refreshInterval
    }
}

struct PlanOutcome: Equatable {
    let plan: Recommendations
    let status: PlanStatus?
}

struct AnalyzeOutcome: Equatable {
    let id: String
    let createdAt: Date
    let result: ScanResult
    let contextTags: [String]
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


