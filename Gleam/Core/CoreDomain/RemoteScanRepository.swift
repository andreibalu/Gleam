import Foundation

struct RemoteScanRepository: ScanRepository {
    private let httpClient: HTTPClient
    private let authRepository: any AuthRepository

    init(httpClient: HTTPClient, authRepository: any AuthRepository) {
        self.httpClient = httpClient
        self.authRepository = authRepository
    }

    func analyze(imageData: Data) async throws -> ScanResult {
        guard !imageData.isEmpty else { throw AppError.invalidImage }

        let url = APIConfiguration.baseURL.appendingPathComponent("analyze")
        let payload = AnalyzePayload(image: imageData.base64EncodedString())
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
}

private struct AnalyzeResponse: Decodable {
    let result: ScanResult
}

private struct EmptyPayload: Encodable {}
