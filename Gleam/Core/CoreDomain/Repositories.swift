import Foundation

protocol ScanRepository {
    func analyze(imageData: Data) async throws -> ScanResult
    func fetchLatest() async throws -> ScanResult?
}

protocol HistoryRepository {
    func list() async throws -> [ScanResult]
}

protocol AuthRepository {
    func currentUserId() async -> String?
    func authToken() async throws -> String?
}


