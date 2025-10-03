import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

enum FirebaseAuthRepositoryError: LocalizedError {
    case missingClientID
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Missing Google client configuration."
        case .missingIDToken:
            return "Unable to retrieve Google ID token."
        }
    }
}

final class FirebaseAuthRepository: AuthRepository {
    private let auth: Auth

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    func currentUserId() async -> String? {
        auth.currentUser?.uid
    }

    func authToken() async throws -> String? {
        guard let user = auth.currentUser else { return nil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            user.getIDToken(completion: { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: token)
                }
            })
        }
    }

    func signInWithGoogle(presentingController: UIViewController) async throws {
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
            if auth.currentUser != nil { return }
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw FirebaseAuthRepositoryError.missingClientID
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw FirebaseAuthRepositoryError.missingIDToken
        }

        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            auth.signIn(with: credential) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
