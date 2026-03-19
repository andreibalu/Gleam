import StoreKit
import SwiftUI

/// Manages StoreKit 2 subscriptions for Gleam Pro.
///
/// Inject as `@StateObject` in `GleamApp` and pass down via `.environmentObject`.
/// Product IDs must match exactly what is configured in App Store Connect (or Gleam.storekit for local testing).
@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Product IDs

    static let monthlyID = "com.gleam.pro.monthly"
    static let yearlyID  = "com.gleam.pro.yearly"

    static let allProductIDs: Set<String> = [monthlyID, yearlyID]

    // MARK: - Published State

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String? = nil
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private

    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        transactionListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshPremiumStatus() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API

    /// Purchase a product. Throws if the purchase fails or is cancelled.
    func purchase(_ product: Product) async throws {
        isLoading = true
        defer { isLoading = false }
        purchaseError = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshPremiumStatus()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    /// Restores previous purchases by re-checking entitlements.
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        await refreshPremiumStatus()
    }

    /// Returns the monthly product, if loaded.
    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyID }
    }

    /// Returns the yearly product, if loaded.
    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyID }
    }

    // MARK: - Private Helpers

    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            // Sort: monthly first, yearly second
            products = fetched.sorted { a, _ in a.id == Self.monthlyID }
        } catch {
            print("[SubscriptionManager] Failed to load products: \(error)")
        }
    }

    private func refreshPremiumStatus() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productType == .autoRenewable,
               transaction.revocationDate == nil {
                hasActive = true
                break
            }
        }
        isPremium = hasActive
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await self.refreshPremiumStatus()
                    await transaction.finish()
                } catch {
                    print("[SubscriptionManager] Transaction verification failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Purchase verification failed. Please try again."
        }
    }
}
