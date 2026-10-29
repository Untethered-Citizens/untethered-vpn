import Foundation
import NetworkExtension
import Testing
@testable import UntetheredVPN

struct AutoConnectTests {

    @Test func connectsOnEveryKindOfNetwork() throws {
        let rules = AutoConnect.rules()
        try #require(rules.count == 1)
        let rule = try #require(rules[0] as? NEOnDemandRuleConnect)
        #expect(rule.interfaceTypeMatch == .any)
        #expect(rule.ssidMatch == nil)
        #expect(rule.dnsSearchDomainMatch == nil)
        #expect(rule.probeURL == nil)
    }

    @Test func turnsOffEveryOtherProfile() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        #expect(AutoConnect.othersToTurnOff(for: a, automatic: [b]) == [b])
        #expect(Set(AutoConnect.othersToTurnOff(for: a, automatic: [a, b, c])) == [b, c])
    }

    @Test func leavesTheProfileItself() {
        let a = UUID()
        #expect(AutoConnect.othersToTurnOff(for: a, automatic: [a]).isEmpty)
        #expect(AutoConnect.othersToTurnOff(for: a, automatic: []).isEmpty)
    }

    @Test func notesNameTheProfileAndWhy() {
        #expect(AutoConnect.TurnedOff.disconnected("Home").message
            == "Connect Automatically is now off for “Home”, so it stays disconnected. To turn it back on, open Details.")
        #expect(AutoConnect.TurnedOff.replaced("Cottage").message
            == "Connect Automatically is now off for “Cottage”, because only one profile can connect automatically.")
    }
}
