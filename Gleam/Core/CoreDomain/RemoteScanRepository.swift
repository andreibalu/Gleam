import Foundation

struct RemoteScanRepository: ScanRepository {
    private let httpClient: HTTPClient
    private let authRepository: any AuthRepository
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        return iso8601FallbackFormatter.date(from: string)
    }

    init(httpClient: HTTPClient, authRepository: any AuthRepository) {
        self.httpClient = httpClient
        self.authRepository = authRepository
    }

    func analyze(
        imageData: Data,
        tags: [String],
        previousTakeaways: [String],
        recentTagHistory: [[String]]
    ) async throws -> AnalyzeOutcome {
        guard !imageData.isEmpty else { throw AppError.invalidImage }

        let url = APIConfiguration.analyzeURL
        let payload = AnalyzePayload(
            image: imageData.base64EncodedString(),
            tags: tags,
            previousTakeaways: previousTakeaways,
            tagHistory: recentTagHistory
        )
        let headers = try await authorizationHeaders()

        do {
            let response: AnalyzeResponse = try await httpClient.send(
                url: url,
                method: "POST",
                headers: headers,
                body: payload
            )
            let identifier = response.id ?? UUID().uuidString
            let contextTags = response.contextTags ?? []
            let createdAt = response.createdAt ?? Date()
            return AnalyzeOutcome(
                id: identifier,
                createdAt: createdAt,
                result: response.result,
                contextTags: contextTags
            )
        } catch {
            throw mapError(error)
        }
    }

    func fetchLatest() async throws -> ScanResult? {
        let url = APIConfiguration.historyLatestURL
        let headers = try await authorizationHeaders()

        do {
            let response: AnalyzeResponse = try await httpClient.send(
                url: url,
                method: "GET",
                headers: headers,
                body: Optional<EmptyPayload>.none
            )
            return response.result
        } catch let apiError as APIError {
            if case let .requestFailed(statusCode) = apiError, statusCode == 404 {
                return nil
            }
            throw mapError(apiError)
        } catch {
            throw mapError(error)
        }
    }

    func fetchLatestPlan() async throws -> PlanOutcome? {
        let url = APIConfiguration.planLatestURL
        let headers = try await authorizationHeaders()

        do {
            let response: PlanResponse = try await httpClient.send(
                url: url,
                method: "GET",
                headers: headers,
                body: Optional<EmptyPayload>.none
            )
            let status = response.meta?.toPlanStatus()
            return PlanOutcome(plan: response.plan, status: status)
        } catch let apiError as APIError {
            if case let .requestFailed(statusCode) = apiError, statusCode == 404 {
                return nil
            }
            throw mapError(apiError)
        } catch {
            throw mapError(error)
        }
    }

    func fetchHistory(limit: Int) async throws -> [HistoryItem] {
        var components = URLComponents(url: APIConfiguration.historyURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]

        guard let url = components?.url else {
            throw AppError.network
        }

        let headers = try await authorizationHeaders()

        do {
            let response: HistoryListResponse = try await httpClient.send(
                url: url,
                method: "GET",
                headers: headers,
                body: Optional<EmptyPayload>.none
            )
            return response.items.map { entry in
                HistoryItem(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    result: entry.result,
                    contextTags: entry.contextTags
                )
            }
        } catch let apiError as APIError {
            if case let .requestFailed(statusCode) = apiError, statusCode == 404 {
                return []
            }
            throw mapError(apiError)
        } catch {
            throw mapError(error)
        }
    }

    func deleteHistoryItem(id: String) async throws {
        let url = APIConfiguration.historyURL
        let headers = try await authorizationHeaders()

        do {
            let _: DeleteResponse = try await httpClient.send(
                url: url,
                method: "DELETE",
                headers: headers,
                body: DeletePayload(id: id)
            )
        } catch let apiError as APIError {
            throw mapError(apiError)
        } catch {
            throw mapError(error)
        }
    }

    private func mapError(_ error: Error) -> AppError {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidURL:
                return .network
            case .requestFailed(let statusCode):
                switch statusCode {
                case 400:
                    // 400 from plan endpoint means invalid request data, not invalid image
                    return .unknown
                case 401, 403:
                    return .unauthorized
                default:
                    return .network
                }
            case .decoding:
                return .decoding
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }

        return .unknown
    }

    private func authorizationHeaders() async throws -> [String: String] {
        if let token = try await authRepository.authToken(), !token.isEmpty {
            return ["Authorization": "Bearer \(token)"]
        }
        return [:]
    }
}

private struct AnalyzePayload: Encodable {
    let image: String
    let tags: [String]
    let previousTakeaways: [String]
    let tagHistory: [[String]]
}

private struct AnalyzeResponse: Decodable {
    let id: String?
    let result: ScanResult
    let contextTags: [String]?
    let createdAt: Date?
    let streak: StreakSnapshot?

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case contextTags
        case createdAt
        case streak
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        result = try container.decode(ScanResult.self, forKey: .result)
        contextTags = try container.decodeIfPresent([String].self, forKey: .contextTags)
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = RemoteScanRepository.parseDate(createdAtString)
        } else {
            createdAt = nil
        }
        streak = try container.decodeIfPresent(StreakSnapshot.self, forKey: .streak)
    }
}

private struct EmptyPayload: Encodable {}

private struct DeletePayload: Encodable {
    let id: String
}

private struct DeleteResponse: Decodable {
    let success: Bool
}

private struct PlanResponse: Decodable {
    let plan: Recommendations
    let meta: PlanResponseMeta?
}

private struct PlanResponseMeta: Decodable {
    let source: String
    let unchanged: Bool
    let reason: String?
    let inputHash: String?
    let updatedAt: String?
    let totalScans: Int?
    let scansUntilNextPlan: Int?
    let scansSinceLastPlan: Int?
    let latestPlanScanCount: Int?
    let planAvailable: Bool?
    let nextPlanAtScanCount: Int?
    let refreshInterval: Int?

    func toPlanStatus() -> PlanStatus? {
        guard let planSource = PlanSource(rawValue: source) else {
            return nil
        }
        let planReason = reason.flatMap { PlanStatusReason(rawValue: $0) }
        let updatedDate = updatedAt.flatMap { RemoteScanRepository.parseDate($0) }
        return PlanStatus(
            source: planSource,
            isUnchanged: unchanged,
            reason: planReason,
            inputHash: inputHash,
            updatedAt: updatedDate,
            totalScans: totalScans,
            scansUntilNextPlan: scansUntilNextPlan,
            scansSinceLastPlan: scansSinceLastPlan,
            latestPlanScanCount: latestPlanScanCount,
            planAvailable: planAvailable,
            nextPlanAtScanCount: nextPlanAtScanCount,
            refreshInterval: refreshInterval
        )
    }
}

private struct StreakSnapshot: Decodable {
    let current: Int
    let best: Int
    let lastScanDate: Date?

    private enum CodingKeys: String, CodingKey {
        case current
        case best
        case lastScanDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decode(Int.self, forKey: .current)
        best = try container.decode(Int.self, forKey: .best)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .lastScanDate) {
            lastScanDate = RemoteScanRepository.parseDate(dateString)
        } else {
            lastScanDate = nil
        }
    }
}

private struct HistoryListResponse: Decodable {
    let items: [HistoryEntry]
}

private struct HistoryEntry: Decodable {
    let id: String
    let result: ScanResult
    let contextTags: [String]
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case contextTags
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        result = try container.decode(ScanResult.self, forKey: .result)
        contextTags = try container.decodeIfPresent([String].self, forKey: .contextTags) ?? []
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt),
           let date = RemoteScanRepository.parseDate(createdAtString) {
            createdAt = date
        } else {
            createdAt = Date()
        }
    }
}
