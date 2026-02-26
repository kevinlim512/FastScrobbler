import Foundation
import SwiftUI

/// Legacy placeholder: Pro is no longer sold and all scrobble controls are available to everyone.
@MainActor
final class ProPurchaseManager: ObservableObject {
    static let shared = ProPurchaseManager()

    @Published private(set) var isPro: Bool = true

    private init() {}

    func startIfNeeded() async {}
}

/// Legacy placeholder view (no longer reachable from the app UI).
@MainActor
struct ProUpgradeView: View {
    let showsCloseButton: Bool
    let onBack: (() -> Void)?

    init(showsCloseButton: Bool = true, onBack: (() -> Void)? = nil) {
        self.showsCloseButton = showsCloseButton
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("FastScrobbler")
                .font(.title.weight(.bold))
            Text("All features are now available by default.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
