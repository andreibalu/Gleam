import Foundation

struct RemoteScanRepository: ScanRepository {
    private let httpClient: HTTPClient
    private let authRepository: any AuthRepository

    init(httpClient: HTTPClient, authRepository: any AuthRepository) {
        self.httpClient = httpClient
        self.authRepository = authRepository
    }

    func analyze(
        imageData: Data,
        tags: [String],
        previousTakeaways: [String],
        recentTagHistory: [[String]]
    ) async throws -> ScanResult {
        guard !imageData.isEmpty else { throw AppError.invalidImage }

        let url = APIConfiguration.baseURL.appendingPathComponent("analyze")
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
            return response.result
        } catch {
            throw mapError(error)
        }
    }

    func generatePlan(history: [PlanHistoryContext]) async throws -> Recommendations {
        let url = APIConfiguration.baseURL.appendingPathComponent("plan")
        let headers = try await authorizationHeaders()
        let formatter = ISO8601DateFormatter()
        let payload = PlanPayload(
            history: history.map { context in
                PlanSnapshotPayload(
                    capturedAt: formatter.string(from: context.capturedAt),
                    whitenessScore: context.whitenessScore,
                    shade: context.shade,
                    detectedIssues: context.detectedIssues,
                    lifestyleTags: context.lifestyleTags,
                    personalTakeaway: context.personalTakeaway
                )
            }
        )

        do {
            let response: PlanResponse = try await httpClient.send(
                url: url,
                method: "POST",
                headers: headers,
                body: payload
            )
            return response.plan
        } catch {
            throw mapError(error)
        }
    }

    func fetchLatest() async throws -> ScanResult? {
        let url = APIConfiguration.baseURL.appendingPathComponent("history/latest")
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

    private func mapError(_ error: Error) -> AppError {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidURL:
                return .network
            case .requestFailed(let statusCode):
                switch statusCode {
                case 400:
                    return .invalidImage
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
    let result: ScanResult
}

private struct EmptyPayload: Encodable {}

private struct PlanPayload: Encodable {
    let history: [PlanSnapshotPayload]
}

private struct PlanSnapshotPayload: Encodable {
    let capturedAt: String
    let whitenessScore: Int
    let shade: String
    let detectedIssues: [DetectedIssue]
    let lifestyleTags: [String]
    let personalTakeaway: String
}

private struct PlanResponse: Decodable {
    let plan: Recommendations
}
