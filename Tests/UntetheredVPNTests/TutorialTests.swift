import Foundation
import Testing
import UIKit
@testable import UntetheredVPN

struct TutorialTests {

    // MARK: - When it's offered

    private func freshDefaults() -> UserDefaults {
        let name = "TutorialTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func offeredOnceWithNoProfiles() {
        let prompt = TutorialPrompt(defaults: freshDefaults())
        #expect(prompt.shouldOffer(hasProfiles: false))
        prompt.markOffered()
        #expect(!prompt.shouldOffer(hasProfiles: false))
    }

    @Test func notOfferedWhenProfilesExist() {
        let prompt = TutorialPrompt(defaults: freshDefaults())
        #expect(!prompt.shouldOffer(hasProfiles: true))
    }

    // MARK: - Cards

    @Test func sixCardsWithTitles() {
        #expect(TutorialCard.allCases.count == 6)
        #expect(TutorialCard.allCases.map(\.rawValue) == Array(0..<6))
        #expect(TutorialCard.allCases.allSatisfy { !$0.title.isEmpty })
    }

    /// A missing SF Symbol draws nothing, so check every one the cards use.
    @Test(arguments: TutorialCard.symbols + ["questionmark.circle"])
    func symbolExists(name: String) {
        #expect(UIImage(systemName: name) != nil)
    }

    @Test(arguments: ["ut.phone", "ut.keyboard", "ut.tv.connected"])
    func appSymbolExists(name: String) {
        #expect(UIImage(named: name) != nil)
    }

    // MARK: - The QR code's link

    /// The QR code opens the README section by its anchor, which GitHub
    /// makes from the heading. Renaming the heading would break the link
    /// in every installed copy, so check it still matches.
    @Test func serverGuideAnchorMatchesReadme() throws {
        let readme = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "README.md")
        let text = try String(contentsOf: readme, encoding: .utf8)
        let anchors = text.split(separator: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { Self.githubAnchor(String($0.dropFirst(3))) }
        let fragment = try #require(Tutorial.serverGuideURL.fragment())
        #expect(anchors.contains(fragment))
        #expect(Tutorial.serverGuideURL.host() == "github.com")
        #expect(Tutorial.serverGuideURL.scheme == "https")
    }

    @Test func anchorRule() {
        #expect(Self.githubAnchor("Set up a WireGuard server") == "set-up-a-wireguard-server")
        #expect(Self.githubAnchor("Status: beta") == "status-beta")
    }

    /// GitHub's rule for heading anchors: lowercase, drop punctuation other
    /// than hyphens and underscores, spaces become hyphens.
    static func githubAnchor(_ heading: String) -> String {
        String(heading.lowercased().compactMap { character -> Character? in
            if character == " " { return "-" }
            if character.isLetter || character.isNumber || character == "-" || character == "_" { return character }
            return nil
        })
    }
}
