import Foundation
import UIKit

struct FakeAuthRepository: AuthRepository {
    func currentUserId() async -> String? {
        "preview-user"
    }

    func authToken() async throws -> String? {
        nil
    }

    func signInWithGoogle(presentingController: UIViewController) async throws {}

    func signOut() throws {}

    func deleteAccount() async throws {}
}
