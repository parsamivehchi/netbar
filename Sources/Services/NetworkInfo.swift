import Foundation

/// One-shot local network facts. Called on panel open only - never on the sampling path.
enum NetworkInfo {
    /// First IPv4 address bound to the given interface.
    static func localIPv4(interface: String) -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let entry = ptr {
            let ifa = entry.pointee
            if let addr = ifa.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == interface {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    /// BSD names of interfaces that are up, running and carry an IPv4 address: the candidates
    /// for the panel's interface picker (v1.4). Loopback and Apple's link-local plumbing
    /// (awdl0, llw0, anpi*, ap1, bridge*) are dropped; nobody wants to meter those.
    static func upInterfaces() -> [String] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var names = Set<String>()
        var ptr = ifaddrPtr
        while let entry = ptr {
            let ifa = entry.pointee
            ptr = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(bitPattern: ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard !isPlumbing(name) else { continue }
            names.insert(name)
        }
        return names.sorted()
    }

    private static func isPlumbing(_ name: String) -> Bool {
        name == "ap1" || name.hasPrefix("awdl") || name.hasPrefix("llw")
            || name.hasPrefix("anpi") || name.hasPrefix("bridge")
    }
}
