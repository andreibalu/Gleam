import Foundation
import UIKit

protocol ScanRepository {
    func analyze(imageData: Data, tags: [String], previousTakeaways: [String]) async throws -> ScanResult
    func generatePlan(history: [PlanHistoryContext]) async throws -> Recommendations
    func fetchLatest() async throws -> ScanResult?
}

protocol HistoryRepository {
    func list() async throws -> [HistoryItem]
    func delete(id: String) async throws
}

protocol AuthRepository {
    func currentUserId() async -> String?
    func authToken() async throws -> String?
    func signInWithGoogle(presentingController: UIViewController) async throws
}


