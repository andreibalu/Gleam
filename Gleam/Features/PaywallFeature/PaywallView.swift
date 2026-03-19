import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PaywallPlan = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.top, AppSpacing.xl)

                    // Feature list
                    featureList
                        .padding(.top, AppSpacing.l)

                    // Plan picker
                    planPicker
                        .padding(.top, AppSpacing.xl)

                    // CTA
                    ctaSection
                        .padding(.top, AppSpacing.l)
                        .padding(.bottom, AppSpacing.xl)
                }
                .padding(.horizontal, AppSpacing.l)
            }

            // Dismiss button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(AppSpacing.m)
                    }
                }
                Spacer()
            }
        }
        .alert("Purchase Failed", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, AppSpacing.xs)

            Text("Gleam Pro")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Unlock your best smile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(spacing: AppSpacing.m) {
            PaywallFeatureRow(
                icon: "infinity",
                title: "Unlimited Scans",
                subtitle: "Scan as many times a day as you like"
            )
            PaywallFeatureRow(
                icon: "brain.head.profile",
                title: "AI Personalized Plans",
                subtitle: "Care plans built from your scan history"
            )
            PaywallFeatureRow(
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                title: "Full Scan History",
                subtitle: "Every result stored, trends always visible"
            )
        }
        .padding(AppSpacing.m)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var planPicker: some View {
        VStack(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                PlanCard(
                    plan: .monthly,
                    product: subscriptionManager.monthlyProduct,
                    isSelected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
                PlanCard(
                    plan: .yearly,
                    product: subscriptionManager.yearlyProduct,
                    isSelected: selectedPlan == .yearly
                ) {
                    selectedPlan = .yearly
                }
            }

            if selectedPlan == .yearly {
                Text("Save ~40% compared to monthly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: AppSpacing.m) {
            Button {
                Task { await handlePurchase() }
            } label: {
                HStack(spacing: AppSpacing.s) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text(isPurchasing ? "Processing…" : "Subscribe Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .buttonStyle(FloatingPrimaryButtonStyle())
            .disabled(isPurchasing || selectedProduct == nil)

            Button {
                Task { await handleRestore() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(isPurchasing)

            Text("Subscription renews automatically. Cancel anytime in Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private var selectedProduct: StoreKit.Product? {
        switch selectedPlan {
        case .monthly: return subscriptionManager.monthlyProduct
        case .yearly:  return subscriptionManager.yearlyProduct
        }
    }

    private func handlePurchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await subscriptionManager.purchase(product)
            if subscriptionManager.isPremium { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleRestore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        await subscriptionManager.restorePurchases()
        if subscriptionManager.isPremium { dismiss() }
    }
}

// MARK: - Supporting Types

private enum PaywallPlan {
    case monthly
    case yearly
}

// MARK: - Plan Card

private struct PlanCard: View {
    let plan: PaywallPlan
    let product: StoreKit.Product?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xs) {
                if plan == .yearly {
                    Text("BEST VALUE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                } else {
                    // Placeholder to keep heights equal
                    Text(" ")
                        .font(.caption2)
                        .padding(.vertical, 3)
                        .opacity(0)
                }

                Text(plan == .monthly ? "Monthly" : "Yearly")
                    .font(.headline)
                    .fontWeight(.semibold)

                if let product {
                    if plan == .yearly {
                        Text(product.displayPrice)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("per year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(product.displayPrice)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("per month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.m)
            .padding(.horizontal, AppSpacing.s)
            .background(isSelected ? AppColors.card : Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? LinearGradient(
                            colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                            startPoint: .leading, endPoint: .trailing
                          )
                        : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing),
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.15) : .clear, radius: 8, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Row

private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            Image(systemName: icon)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
