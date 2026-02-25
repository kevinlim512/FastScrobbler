import Foundation
import OSLog
import StoreKit
import SwiftUI

@MainActor
final class ProPurchaseManager: ObservableObject {
    static let shared = ProPurchaseManager()

    enum Constants {
        static let productID = "com.kevin.FastScrobbler.pro"
        static let fallbackUSDPriceText = "$2.00"
    }

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var lastErrorText: String?

    private let logger = Logger(subsystem: "FastScrobbler", category: "ProPurchaseManager")
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {
        let cached = ProEntitlement.cachedIsPro()
        self.isPro = cached
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

#if os(macOS)
        // The macOS app ships with Pro features enabled for everyone.
        if !isPro { isPro = true }
        AppGroup.userDefaults.set(true, forKey: ProEntitlement.cachedEntitledKey)
        return
#endif

        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if transaction.productID == Constants.productID {
                    await refreshEntitlement()
                }
                await transaction.finish()
            }
        }

        await refreshEntitlement()
        await loadProduct()
    }

    func loadProduct() async {
#if os(macOS)
        return
#endif
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Constants.productID])
            product = products.first
        } catch {
            lastErrorText = error.localizedDescription
            logger.warning("failed to load product: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase() async {
#if os(macOS)
        return
#endif
        lastErrorText = nil
        guard let product else {
            await loadProduct()
            guard self.product != nil else { return }
            return await purchase()
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                await refreshEntitlement()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorText = error.localizedDescription
            logger.warning("purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restorePurchases() async {
#if os(macOS)
        return
#endif
        lastErrorText = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastErrorText = error.localizedDescription
        }
    }

    func displayPriceText() -> String {
        product?.displayPrice ?? Constants.fallbackUSDPriceText
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Constants.productID {
                entitled = true
                break
            }
        }

        if isPro != entitled {
            isPro = entitled
        }
        AppGroup.userDefaults.set(entitled, forKey: ProEntitlement.cachedEntitledKey)
    }
}

@MainActor
struct ProUpgradeView: View {
    @EnvironmentObject private var pro: ProPurchaseManager
    @Environment(\.dismiss) private var dismiss

    let showsCloseButton: Bool
    let onBack: (() -> Void)?
#if os(macOS)
    let showsMacBackButton: Bool
#endif

    @State private var isShowingThankYou = false
    @State private var didInitiatePurchase = false

#if os(macOS)
    init(
        showsCloseButton: Bool = true,
        onBack: (() -> Void)? = nil,
        showsMacBackButton: Bool = true
    ) {
        self.showsCloseButton = showsCloseButton
        self.onBack = onBack
        self.showsMacBackButton = showsMacBackButton
    }
#else
    init(
        showsCloseButton: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.showsCloseButton = showsCloseButton
        self.onBack = onBack
    }
#endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FastScrobbler Pro")
                        .font(.title.weight(.bold))
                    Text("Upgrade to unlock more scrobble controls.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(
                        systemImage: "heart.fill",
                        title: "Love favourites on Last.fm",
                        subtitle: "When you tap the heart in Apple Music for the currently playing track, it’s also marked as Loved on Last.fm."
                    )
                    featureRow(
                        systemImage: "slider.horizontal.3",
                        title: "Pick scrobble threshold",
                        subtitle: "Choose when a track scrobbles: 10%, 25%, 50%, or 75% of the song duration."
                    )
                    featureRow(
                        systemImage: "person.2.fill",
                        title: "Scrobble using album artist",
                        subtitle: "Uses the song’s album artist for the Artist field when scrobbling."
                    )
                    featureRow(
                        systemImage: "heart.circle.fill",
                        title: "Support development of the app",
                        subtitle: "Your upgrade helps keep FastScrobbler fast, simple, and improving."
                    )
                }

                Button {
                    Task {
                        didInitiatePurchase = true
                        if pro.product == nil {
                            await pro.loadProduct()
                            if pro.product != nil {
                                await pro.purchase()
                            }
                        } else {
                            await pro.purchase()
                        }

                        if !pro.isPro {
                            didInitiatePurchase = false
                        }
                    }
                } label: {
                    if pro.isPro {
                        Text("Purchased")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else if pro.isPurchasing || (pro.isLoading && pro.product == nil) {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else if pro.product != nil {
                        Text("Buy \(pro.displayPriceText())")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    } else {
                        Text("Retry")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
                .disabled(pro.isPro || pro.isPurchasing || (pro.isLoading && pro.product == nil))

                if pro.isPro {
                    Text("You’re upgraded.")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }

                if let err = pro.lastErrorText {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await pro.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()

                Text("FastScrobbler is not affiliated with Last.fm.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding()
#if os(macOS)
            .padding(.top, MacFloatingBarLayout.contentTopPadding)
#endif
        }
#if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            if showsMacBackButton {
                MacFloatingCircleButton(
                    systemImage: "chevron.left",
                    help: "Back",
                    accessibilityLabel: "Back",
                    action: {
                        if let onBack {
                            onBack()
                        } else {
                            dismiss()
                        }
                    }
                )
                .padding(.top, 10)
                .padding(.leading, 10)
            }
        }
#endif
        .onChange(of: pro.isPro) { isPro in
            guard didInitiatePurchase, isPro else { return }
            didInitiatePurchase = false
            isShowingThankYou = true
        }
        .task {
            await pro.startIfNeeded()
        }
#if os(iOS)
        .fullScreenCover(isPresented: $isShowingThankYou) {
            ProThankYouView {
                isShowingThankYou = false
                dismiss()
            }
        }
#else
        .overlay {
            if isShowingThankYou {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isShowingThankYou = false
                        }

                    ProThankYouView {
                        isShowingThankYou = false
                        dismiss()
                    }
                    .frame(maxWidth: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 10)
                    .padding(24)
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: isShowingThankYou)
            }
        }
#endif
        .toolbar {
            if showsCloseButton {
#if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        IOSCloseButtonLabel(style: .plain)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
#else
                ToolbarItem {
                    Button {
                        dismiss()
                    } label: {
                        IOSCloseButtonLabel(style: .plain)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
#endif
            }
        }
    }

    private func featureRow(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

struct ProThankYouView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.pink.opacity(0.35),
                    Color.purple.opacity(0.28),
                    Color.blue.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "heart.fill")
                    .font(.system(size: 52, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.pink, .white)
                    .frame(width: 96, height: 96)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 10)

                Text("You’re upgraded!")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Thanks for supporting FastScrobbler Pro.\nEnjoy the extra scrobble controls.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    onDone()
                } label: {
                    Text("Awesome!")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
            }
            .padding()
        }
    }
}
