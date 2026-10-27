import Network
import WireGuardKit

extension WireGuardConfig {

    /// The config in WireGuardKit's types. Our parser has already validated
    /// every value, so a nil here means the two disagree about a format.
    func tunnelConfiguration(named name: String) -> TunnelConfiguration? {
        guard let privateKey = PrivateKey(base64Key: interface.privateKey.base64) else { return nil }
        var wgInterface = InterfaceConfiguration(privateKey: privateKey)
        wgInterface.listenPort = interface.listenPort
        wgInterface.mtu = interface.mtu
        wgInterface.dnsSearch = interface.dnsSearchDomains
        for address in interface.addresses {
            guard let range = IPAddressRange(from: address.description) else { return nil }
            wgInterface.addresses.append(range)
        }
        for server in interface.dnsServers {
            guard let dns = DNSServer(from: server) else { return nil }
            wgInterface.dns.append(dns)
        }

        var wgPeers: [PeerConfiguration] = []
        for peer in peers {
            guard let publicKey = PublicKey(base64Key: peer.publicKey.base64),
                  let endpoint = Endpoint(from: peer.endpoint.description) else { return nil }
            var wgPeer = PeerConfiguration(publicKey: publicKey)
            if let psk = peer.presharedKey {
                guard let presharedKey = PreSharedKey(base64Key: psk.base64) else { return nil }
                wgPeer.preSharedKey = presharedKey
            }
            wgPeer.endpoint = endpoint
            wgPeer.persistentKeepAlive = peer.persistentKeepalive
            for allowed in peer.allowedIPs {
                guard let range = IPAddressRange(from: allowed.description) else { return nil }
                wgPeer.allowedIPs.append(range)
            }
            wgPeers.append(wgPeer)
        }
        return TunnelConfiguration(name: name, interface: wgInterface, peers: wgPeers)
    }
}
