import Darwin
import Foundation

/// Finds the Apple TV's IPv4 address on the local network (Ethernet or
/// Wi-Fi), for the import server to listen on and the QR code to show.
enum LocalAddress {

    struct Interface: Equatable {
        let name: String
        let address: String
        let isUp: Bool
    }

    /// The address to use, or nil when the TV isn't on a local network.
    static func current() -> String? {
        choose(from: interfaces())
    }

    /// Picks an address on a physical interface (`en0`, `en1`, …), never
    /// the loopback or a VPN tunnel (`utun…`), so the server can't be
    /// reached through a connected WireGuard tunnel. Private ranges come
    /// first; link-local (169.254.x.x) means no working network, so it's
    /// skipped.
    static func choose(from interfaces: [Interface]) -> String? {
        let candidates = interfaces.filter {
            $0.isUp && $0.name.hasPrefix("en") && !$0.address.hasPrefix("169.254.")
        }
        let ordered = candidates.sorted { lhs, rhs in
            let lhsPrivate = isPrivate(lhs.address), rhsPrivate = isPrivate(rhs.address)
            if lhsPrivate != rhsPrivate { return lhsPrivate }
            return lhs.name.compare(rhs.name, options: .numeric) == .orderedAscending
        }
        return ordered.first?.address
    }

    /// 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16 (RFC 1918).
    static func isPrivate(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }

    private static func interfaces() -> [Interface] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var result: [Interface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let socketAddress = entry.ifa_addr, socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let flags = Int32(entry.ifa_flags)
            result.append(Interface(
                name: String(cString: entry.ifa_name),
                address: String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
                isUp: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 && flags & IFF_LOOPBACK == 0
            ))
        }
        return result
    }
}
