import Foundation
import Testing
@testable import UntetheredVPN

struct ProfileNameTests {

    @Test func acceptsANewName() {
        #expect(ProfileName.problem("Cottage", otherNames: ["Home", "Office"]) == nil)
    }

    @Test(arguments: ["Home", "home", "  HOME ", "Ｈｏｍｅ"])
    func refusesANameAlreadyUsed(name: String) {
        let problem = ProfileName.problem(name, otherNames: ["Home", "Office"])
        #expect(problem?.hasPrefix("You already have a profile called") == true)
    }

    @Test func namesTheTakenNameAsTyped() {
        #expect(ProfileName.problem(" home ", otherNames: ["Home"])
            == "You already have a profile called “home”. Choose another name.")
    }

    @Test func accentsMakeADifferentName() {
        #expect(ProfileName.problem("Café", otherNames: ["Cafe"]) == nil)
    }

    @Test func refusesEmptyAndLongNames() {
        #expect(ProfileName.problem("   ", otherNames: []) == "Enter a name, such as Home.")
        #expect(ProfileName.problem(String(repeating: "x", count: ProfileName.maxLength + 1), otherNames: []) != nil)
        #expect(ProfileName.problem(String(repeating: "x", count: ProfileName.maxLength), otherNames: []) == nil)
    }

    @Test func cleanedDropsSurroundingSpaces() {
        #expect(ProfileName.cleaned("  Home Two \n") == "Home Two")
    }

    @Test func draftRefusesAnotherProfilesName() {
        var draft = ProfileDraft()
        draft.otherNames = ["Home"]
        #expect(draft.problem(in: .name)?.hasPrefix("You already have") == true)
        draft.name = "Cottage"
        #expect(draft.problem(in: .name) == nil)
    }

    @Test func draftKeepsItsOwnNameWhenEditing() throws {
        var draft = ProfileDraft()
        draft.privateKey = Fixtures.randomKeyText()
        draft.address = "10.8.0.2/32"
        draft.publicKey = Fixtures.randomKeyText()
        draft.endpoint = "vpn.example.com:51820"
        let profile = try #require(draft.makeProfile())
        var editing = ProfileDraft(editing: profile)
        // The editor passes the other profiles' names, never the profile's own
        editing.otherNames = ["Office"]
        #expect(editing.problem(in: .name) == nil)
    }
}

struct LastUsedProfileTests {

    /// A scratch defaults suite, emptied first so runs don't affect each other.
    func makeDefaults() -> UserDefaults {
        let name = "LastUsedProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func remembersTheLastConnected() {
        let lastUsed = LastUsedProfile(defaults: makeDefaults())
        let (a, b) = (UUID(), UUID())
        #expect(lastUsed.id(among: [a, b]) == nil)
        lastUsed.remember(a)
        lastUsed.remember(b)
        #expect(lastUsed.id(among: [a, b]) == b)
    }

    @Test func ignoresAProfileThatNoLongerExists() {
        let lastUsed = LastUsedProfile(defaults: makeDefaults())
        let (a, b) = (UUID(), UUID())
        lastUsed.remember(a)
        #expect(lastUsed.id(among: [b]) == nil)
    }

    @Test func forgetsOnlyTheRememberedProfile() {
        let lastUsed = LastUsedProfile(defaults: makeDefaults())
        let (a, b) = (UUID(), UUID())
        lastUsed.remember(a)
        lastUsed.forget(b)
        #expect(lastUsed.id(among: [a, b]) == a)
        lastUsed.forget(a)
        #expect(lastUsed.id(among: [a, b]) == nil)
    }

    @Test func storesOnlyTheID() {
        let defaults = makeDefaults()
        let id = UUID()
        LastUsedProfile(defaults: defaults).remember(id)
        #expect(defaults.string(forKey: LastUsedProfile.key) == id.uuidString)
    }

    @Test func worksWithoutDefaults() {
        let lastUsed = LastUsedProfile(defaults: nil)
        lastUsed.remember(UUID())
        #expect(lastUsed.id(among: []) == nil)
    }
}
