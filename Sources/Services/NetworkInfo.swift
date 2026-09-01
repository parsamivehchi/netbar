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
}
