import StoreKit
import SwiftUI

@MainActor
final class ProPurchaseManager: ObservableObject {
    static let shared = ProPurchaseManager()

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var lastErrorMessage: String?

    private var didStart = false
    private var updatesTask: Task<Void, Never>?

    private init() {
        self.isPro = ProEntitlement.isPro
    }

    deinit {
        updatesTask?.cancel()
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

#if os(macOS)
        // Pro is always enabled on macOS; no StoreKit flow.
        setIsPro(true)
        return
#endif
        await loadProductIfNeeded()
        await refreshEntitlements()
        startListeningForTransactionUpdates()
    }

    func purchase() async {
        lastErrorMessage = nil

#if os(macOS)
        setIsPro(true)
        return
#endif
        if product == nil {
            await loadProductIfNeeded()
        }
        guard let product else {
            lastErrorMessage = "Unable to load FastScrobbler Pro."
            return
        }

        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = "Purchase couldn’t be verified."
                    return
                }
                // Optimistically enable Pro immediately after verification, then re-check entitlements.
                if transaction.productID == ProEntitlement.productID {
                    setIsPro(true)
                }
                await transaction.finish()
                await refreshEntitlements()

            case .userCancelled:
                break

            case .pending:
                lastErrorMessage = "Purchase pending approval."

            @unknown default:
                break
            }
        } catch {
            if error is CancellationError { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

#if os(macOS)
        setIsPro(true)
        return
#endif
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            if error is CancellationError { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    private func setIsPro(_ newValue: Bool) {
        if isPro != newValue {
            isPro = newValue
        }
        ProEntitlement.isPro = newValue
    }

    private func loadProductIfNeeded() async {
        guard product == nil else { return }
        do {
            let products = try await Product.products(for: [ProEntitlement.productID])
            product = products.first
        } catch {
            if error is CancellationError { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == ProEntitlement.productID {
                purchased = true
                break
            }
        }
        setIsPro(purchased)
    }

    private func startListeningForTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                guard transaction.productID == ProEntitlement.productID else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}

#if os(iOS)
@MainActor
struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pro: ProPurchaseManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, 24)

                    VStack(spacing: 12) {
                        ProBenefitCard(
                            systemImage: "heart",
                            title: "Love favourites on Last.fm",
                            subtitle: "Favourited tracks in Apple Music are also marked as Loved on Last.fm."
                        )
                        ProBenefitCard(
                            systemImage: "slider.horizontal.3",
                            title: "Pick scrobble threshold",
                            subtitle: "Choose when a track scrobbles: 10%, 25%, 50%, or 75% of the song duration."
                        )
                        ProBenefitCard(
                            systemImage: "person.2",
                            title: "Clean up scrobble metadata",
                            subtitle: "Use album artist when scrobbling, and remove “- EP” / “- Single” from album names."
                        )
                        ProBenefitCard(
                            systemImage: "heart.circle",
                            title: "Support development of the app",
                            subtitle: "Your upgrade helps support future development of FastScrobbler."
                        )
                    }

                    purchaseSection
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            await pro.startIfNeeded()
        }
        .alert("FastScrobbler Pro", isPresented: Binding(
            get: { pro.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pro.lastErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pro.lastErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("FastScrobbler Pro")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text("Upgrade to unlock more scrobble controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var purchaseSection: some View {
        let priceText = pro.product.map { $0.price.formatted($0.priceFormatStyle) } ?? "$1.99"
        let purchaseTitle = pro.isPro ? "Purchased" : "Upgrade for \(priceText)"

        VStack(spacing: 12) {
            Button {
                Task { await pro.purchase() }
            } label: {
                Text(purchaseTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(pro.isPro ? .gray.opacity(0.35) : .blue)
            .disabled(pro.isPro || pro.isPurchasing)

            if pro.isPro {
                Text("You’re upgraded.")
                    .font(.subheadline.weight(.semibold))
            }

            Button {
                Task { await pro.restorePurchases() }
            } label: {
                Text(pro.isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
            .disabled(pro.isRestoring)
        }
    }
}

private struct ProBenefitCard: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
#endif
