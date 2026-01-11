import Foundation
import UIKit

protocol ScanRepository {
    func analyze(
        imageData: Data,
        tags: [String],
        previousTakeaways: [String],
        recentTagHistory: [[String]]
    ) async throws -> AnalyzeOutcome
    func fetchLatest() async throws -> ScanResult?
    func fetchLatestPlan() async throws -> PlanOutcome?
    func fetchHistory(limit: Int) async throws -> [HistoryItem]
    func deleteHistoryItem(id: String) async throws
}

protocol HistoryRepository {
    func list() async throws -> [HistoryItem]
    func delete(id: String) async throws
}

protocol AuthRepository {
    func currentUserId() async -> String?
    func authToken() async throws -> String?
    func signInWithGoogle(presentingController: UIViewController) async throws
    func signOut() throws
    func deleteAccount() async throws
}


