import Foundation
import SystemConfiguration

/// Reads per-interface traffic counters straight from the kernel routing sysctl.
///
/// Efficiency contract (the whole point of this app):
/// - sysctl NET_RT_IFLIST2 with 64-bit if_data64 counters - never getifaddrs, whose
///   if_data counters are u_int32_t and wrap in ~34 s at 1 Gbps.
/// - Counts ONLY the primary interface (SCDynamicStore State:/Network/Global/IPv4).
///   Summing all interfaces double-counts VPN traffic (utun + en0) and picks up awdl0.
/// - The read buffer is grow-only and reused every tick; the walk allocates nothing.
actor NetSampler {
    struct Tick: Sendable {
        var sample: SpeedSample = .zero
        var deltaInBytes: UInt64 = 0
        var deltaOutBytes: UInt64 = 0
        var interfaceName: String?
        var router: String?
    }

    // Local constants: these are C macros and their Swift import is not guaranteed.
    private let rtmIfinfo2: UInt8 = 0x12   // RTM_IFINFO2 (net/route.h)
    private let netRtIflist2: Int32 = 6    // NET_RT_IFLIST2 (sys/socket.h)

    private var buf = [UInt8](repeating: 0, count: 16 * 1024)
    private var store: SCDynamicStore?
    private var cachedName: String?
    private var ifIndex: UInt16 = 0
    private var lastIn: UInt64?
    private var lastOut: UInt64?
    private let clock = ContinuousClock()
    private var lastTime: ContinuousClock.Instant?

    /// Forget the counter baseline (call after display wake so the first delta is not huge).
    func resetBaseline() {
        lastIn = nil
        lastOut = nil
        lastTime = nil
    }

    func sample() -> Tick {
        let now = clock.now
        let (name, router) = primaryInterface()
        if name != cachedName {
            cachedName = name
            ifIndex = name.map { UInt16(truncatingIfNeeded: if_nametoindex($0)) } ?? 0
            lastIn = nil
            lastOut = nil
        }

        var tick = Tick(interfaceName: name, router: router)
        guard ifIndex != 0, let (inBytes, outBytes) = readCounters(ifIndex: ifIndex) else {
            lastIn = nil
            lastOut = nil
            lastTime = now
            return tick
        }
        defer {
            lastIn = inBytes
            lastOut = outBytes
            lastTime = now
        }
        guard let li = lastIn, let lo = lastOut, let lt = lastTime else { return tick }
        let elapsed = lt.duration(to: now)
        let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        guard secs > 0.05 else { return tick }
        // A counter that went backwards means a reset (interface bounce): clamp to 0.
        let dIn = inBytes >= li ? inBytes - li : 0
        let dOut = outBytes >= lo ? outBytes - lo : 0
        tick.deltaInBytes = dIn
        tick.deltaOutBytes = dOut
        tick.sample = SpeedSample(downMbps: Double(dIn) * 8 / secs / 1_000_000,
                                  upMbps: Double(dOut) * 8 / secs / 1_000_000)
        return tick
    }

    // MARK: - Primary interface (SCDynamicStore, one mach lookup per tick)

    private func primaryInterface() -> (name: String?, router: String?) {
        if store == nil {
            store = SCDynamicStoreCreate(nil, "com.parsa.netbar" as CFString, nil, nil)
        }
        guard let store,
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
              let dict = value as? [String: Any] else {
            return (nil, nil)
        }
        return (dict["PrimaryInterface"] as? String, dict["Router"] as? String)
    }

    // MARK: - Counter read (sysctl NET_RT_IFLIST2)

    private func readCounters(ifIndex: UInt16) -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, netRtIflist2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return nil }
        len += 2048  // slack: the table can grow between the size call and the fetch
        if buf.count < len {
            buf = [UInt8](repeating: 0, count: len)
        }
        var actual = buf.count
        guard sysctl(&mib, 6, &buf, &actual, nil, 0) == 0 else { return nil }

        return buf.withUnsafeBytes { raw -> (UInt64, UInt64)? in
            var off = 0
            // Records are packed at ifm_msglen strides with no alignment guarantee:
            // loadUnaligned only, never load(as:).
            while off + 4 <= actual {
                let msglen = Int(raw.loadUnaligned(fromByteOffset: off, as: UInt16.self))
                guard msglen > 0 else { return nil }
                let type = raw.loadUnaligned(fromByteOffset: off + 3, as: UInt8.self)
                if type == rtmIfinfo2, off + MemoryLayout<if_msghdr2>.size <= actual {
                    let msg = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    if msg.ifm_index == ifIndex {
                        return (msg.ifm_data.ifi_ibytes, msg.ifm_data.ifi_obytes)
                    }
                }
                off += msglen
            }
            return nil
        }
    }
}
