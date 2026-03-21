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
#else
        await loadProductIfNeeded()
        await refreshEntitlements()
        startListeningForTransactionUpdates()
#endif
    }

    @discardableResult
    func purchase() async -> Bool {
        lastErrorMessage = nil

#if os(macOS)
        setIsPro(true)
        return true
#else
        if product == nil {
            await loadProductIfNeeded()
        }
        guard let product else {
            lastErrorMessage = "Unable to load FastScrobbler Pro."
            return false
        }

        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = "Purchase couldn’t be verified."
                    return false
                }
                // Optimistically enable Pro immediately after verification, then re-check entitlements.
                let isProTransaction = transaction.productID == ProEntitlement.productID
                if isProTransaction {
                    setIsPro(true)
                }
                await transaction.finish()
                await refreshEntitlements()
                return isProTransaction

            case .userCancelled:
                return false

            case .pending:
                lastErrorMessage = "Purchase pending approval."
                return false

            @unknown default:
                return false
            }
        } catch {
            if error is CancellationError { return false }
            lastErrorMessage = error.localizedDescription
            return false
        }
#endif
    }

    func restorePurchases() async {
        lastErrorMessage = nil

#if os(macOS)
        setIsPro(true)
        return
#else
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            if error is CancellationError { return }
            lastErrorMessage = error.localizedDescription
        }
#endif
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

    @State private var showThankYou = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, 16)

                    VStack(spacing: 12) {
                        ProBenefitCard(
                            systemImage: "heart",
                            title: NSLocalizedString("Love favourites on Last.fm", comment: ""),
                            subtitle: NSLocalizedString("Favourited tracks in Apple Music are also marked as Loved on Last.fm.", comment: "")
                        )
                        ProBenefitCard(
                            systemImage: "slider.horizontal.3",
                            title: NSLocalizedString("Pick scrobble threshold", comment: ""),
                            subtitle: NSLocalizedString("Choose when a track scrobbles: 10%, 25%, 50%, or 75% of the song duration.", comment: "")
                        )
                        ProBenefitCard(
                            systemImage: "person.2",
                            title: NSLocalizedString("Clean up scrobble metadata", comment: ""),
                            subtitle: NSLocalizedString("Replace song artist with album artist when scrobbling, and remove “- EP” / “- Single” from album names.", comment: "")
                        )
                        ProBenefitCard(
                            systemImage: "parentheses",
                            title: NSLocalizedString("Remove brackets", comment: ""),
                            subtitle: NSLocalizedString("Remove brackets from song and album titles by matching keywords, or optionally remove all brackets.", comment: "")
                        )
                        ProBenefitCard(
                            systemImage: "clock.arrow.circlepath",
                            title: NSLocalizedString("Scrobble Listening History from all devices", comment: ""),
                            subtitle: NSLocalizedString("Allow Listening History imports to include plays synced from your other devices.", comment: "")
                        )
                        ProBenefitCard(
                            systemImage: "heart.circle",
                            title: NSLocalizedString("Support development of the app", comment: ""),
                            subtitle: NSLocalizedString("Your upgrade helps support future development of FastScrobbler.", comment: "")
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
        .sheet(isPresented: $showThankYou, onDismiss: { dismiss() }) {
            ProThankYouView()
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
        let priceText = pro.product?.displayPrice
        let purchaseTitle: String = {
            if pro.isPro { return NSLocalizedString("Purchased", comment: "") }
            if let priceText {
                return String.localizedStringWithFormat(NSLocalizedString("Upgrade for %@", comment: ""), priceText)
            }
            return NSLocalizedString("Upgrade", comment: "")
        }()

        VStack(spacing: 12) {
            Button {
                Task {
                    let didPurchase = await pro.purchase()
                    if didPurchase {
                        showThankYou = true
                    }
                }
            } label: {
                Text(purchaseTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(pro.isPro ? .gray.opacity(0.35) : .blue)
            .disabled(pro.isPro || pro.isPurchasing)

            if !pro.isPro {
                Text("One-time purchase. Not a subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if pro.isPro {
                Text("You’re upgraded.")
                    .font(.subheadline.weight(.semibold))
            }

            Button {
                Task { await pro.restorePurchases() }
            } label: {
                Text(pro.isRestoring ? NSLocalizedString("Restoring…", comment: "") : NSLocalizedString("Restore Purchase", comment: ""))
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

private struct ProThankYouView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.pink.opacity(0.20),
                    Color.blue.opacity(0.16),
                    Color.mint.opacity(0.14),
                    Color.purple.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                Circle()
                    .fill(Color.orange.opacity(0.20))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: -140, y: -220)

                Circle()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: 180, y: -160)

                Circle()
                    .fill(Color.pink.opacity(0.16))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .offset(x: 120, y: 260)
            }
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 6)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("Thank you!", comment: ""))
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("You’ve unlocked FastScrobbler Pro!\nYour upgrade helps support future development of FastScrobbler.", comment: ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("Done", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 260, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
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
