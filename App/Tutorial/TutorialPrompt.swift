import Foundation

/// When to offer the How It Works tutorial by itself: once, on a launch
/// with no profiles saved. Someone who already has a profile has got past
/// what it teaches. Only a flag is stored, in the app's own defaults.
struct TutorialPrompt {
    static let key = "howItWorksOffered"

    let defaults: UserDefaults

    func shouldOffer(hasProfiles: Bool) -> Bool {
        !hasProfiles && !defaults.bool(forKey: Self.key)
    }

    func markOffered() {
        defaults.set(true, forKey: Self.key)
    }
}

enum Tutorial {
    /// The README section card 2's QR code opens on the phone. Its fragment
    /// is the heading's anchor, so a test checks it against the README.
    static let serverGuideURL = URL(string: "https://github.com/Untethered-Citizens/untethered-vpn#set-up-a-wireguard-server")!
}
