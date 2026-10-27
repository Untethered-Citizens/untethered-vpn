import SwiftUI

/// Placeholder home screen. Phase 4 replaces it with the profile list and the
/// Connect button.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 120))
                .foregroundStyle(.tint)
            Text("Untethered VPN")
                .font(.largeTitle.bold())
            Text("No profiles yet.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(80)
    }
}

#Preview {
    HomeView()
}
