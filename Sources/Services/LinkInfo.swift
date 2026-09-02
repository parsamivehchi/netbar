import Foundation
import SystemConfiguration

/// What kind of link the primary interface is. Resolved once per interface NAME and cached:
/// SCNetworkInterfaceCopyAll walks the whole configuration and must never run per tick.
enum LinkKind: String, Sendable {
    case wifi, ethernet, vpn, cellular, other

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn: return "lock.shield"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn: return "VPN"
        case .cellular: return "Cellular"
        case .other: return "Link"
        }
    }
}

enum LinkInfo {
    nonisolated(unsafe) private static var cache: [String: LinkKind] = [:]

    static func kind(of bsdName: String) -> LinkKind {
        if let hit = cache[bsdName] { return hit }
        var kind: LinkKind = .other
        if bsdName.hasPrefix("utun") || bsdName.hasPrefix("ipsec") || bsdName.hasPrefix("ppp") || bsdName.hasPrefix("tun") || bsdName.hasPrefix("tap") {
            kind = .vpn
        } else if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in all where (SCNetworkInterfaceGetBSDName(iface) as String?) == bsdName {
                let type = (SCNetworkInterfaceGetInterfaceType(iface) as String?) ?? ""
                if type == (kSCNetworkInterfaceTypeIEEE80211 as String) { kind = .wifi }
                else if type == (kSCNetworkInterfaceTypeEthernet as String) { kind = .ethernet }
                else if type == (kSCNetworkInterfaceTypeWWAN as String) { kind = .cellular }
                else if type == (kSCNetworkInterfaceTypePPP as String) || type == (kSCNetworkInterfaceTypeIPSec as String) { kind = .vpn }
                else { kind = .other }
                break
            }
        }
        cache[bsdName] = kind
        return kind
    }
}
