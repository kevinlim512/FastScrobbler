import Foundation
import SwiftUI

/// Legacy placeholder: Pro is not currently implemented in the app, so all scrobble controls are currently available for all users.
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
