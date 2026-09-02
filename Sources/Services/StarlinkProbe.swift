import Foundation
import Network

/// Is a Starlink dish on this LAN? Every dish answers its gRPC API on the fixed, documented
/// address 192.168.100.1:9200, so one TCP handshake to it is the whole test. LAN-only: the probe
/// never leaves the local network, so it costs zero satellite bytes. Called ONLY from
/// AppViewModel.panelOpened(), never on the sampling path.
///
/// Known blind spot, accepted (netstats documents the same one): a router in bypass mode without
/// a static route to 192.168.100.0/24 makes the dish unreachable and the Starlink row stays hidden.
enum StarlinkProbe {
    static let dishHost = "192.168.100.1"
    static let dishPort: UInt16 = 9200
    /// The dish's own status page (dishy.starlink.com resolves here only through the dish's DNS,
    /// so the numeric form is the one that always works).
    static let dishyURL = URL(string: "http://192.168.100.1")!

    /// True when the dish accepted a TCP connection within `timeout`.
    static func reachable(timeout: Duration = .milliseconds(500)) async -> Bool {
        let conn = NWConnection(host: NWEndpoint.Host(dishHost),
                                port: NWEndpoint.Port(rawValue: dishPort)!,
                                using: .tcp)
        return await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask { await connect(conn) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            // Cancelling the connection resumes the connect task (via .cancelled) if it is still
            // waiting; the group cannot return until both children finish, so this must happen
            // BEFORE the return, not after.
            conn.cancel()
            group.cancelAll()
            return first
        }
    }

    /// Resolves exactly once even though the state handler can fire more than once
    /// (.ready followed by .cancelled).
    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    private static func connect(_ conn: NWConnection) async -> Bool {
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume(returning: true) }
                case .failed, .cancelled:
                    if once.claim() { cont.resume(returning: false) }
                default:
                    break   // .preparing / .waiting: let the timeout decide
                }
            }
            conn.start(queue: .global(qos: .utility))
        }
    }
}
