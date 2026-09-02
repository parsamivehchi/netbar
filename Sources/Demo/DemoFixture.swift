import Foundation

/// Sample data for screenshots, README captures and the public product page.
///
/// PRIVACY CONTRACT: every value here is synthetic by construction - RFC 5737
/// TEST-NET-3 for the public address, a private 10.x LAN, a placeholder SSID.
/// Screenshots are NEVER taken from a live session (the first public shot of
/// NetBar shipped a real SSID and a real WAN IP, 2026-09-01). Activate with
/// `NETBAR_DEMO=1`; add `NETBAR_RENDER_PANEL=/abs/path.png` to render the panel
/// headlessly and exit (see App.swift).
enum DemoFixture {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["NETBAR_DEMO"] == "1"
    }

    /// NETBAR_DEMO_PRIVACY=1 renders the panel with privacy mode on (masked rows).
    static var privacy: Bool {
        ProcessInfo.processInfo.environment["NETBAR_DEMO_PRIVACY"] == "1"
    }

    /// NETBAR_RENDER_LABEL=/abs/path.png renders the stacked menu bar label at 4x and exits.
    static var labelRenderPath: String? {
        ProcessInfo.processInfo.environment["NETBAR_RENDER_LABEL"]
    }

    static var renderPath: String? {
        ProcessInfo.processInfo.environment["NETBAR_RENDER_PANEL"]
    }

    static let ssid = "HomeNet-5G"
    static let interfaceName = "en0"
    static let localIP = "10.0.1.42"
    static let routerIP = "10.0.1.1"
    static let publicIP = "203.0.113.17"   // RFC 5737 documentation range, never routable
    static let current = SpeedSample(downMbps: 512.3, upMbps: 24.6)
    static let totalInBytes: UInt64 = 1_200_000_000
    static let totalOutBytes: UInt64 = 86_000_000

    /// Two minutes of samples, oldest first: a quiet baseline, a burst, then a
    /// sustained download that ends at `current`. Deterministic, no randomness.
    static var samples: [SpeedSample] {
        (0..<60).map { i -> SpeedSample in
            let t = Double(i)
            let down: Double
            let up: Double
            switch i {
            case 0..<18:  down = 8 + 4 * sin(t / 2.5);            up = 1.2 + 0.6 * sin(t / 1.7)
            case 18..<26: down = 60 + 30 * sin((t - 18) / 1.3);   up = 3.5 + 1.5 * sin(t)
            case 26..<40: down = 12 + 6 * sin(t / 2.1);           up = 1.8 + 0.7 * sin(t / 1.9)
            case 40..<52: down = 120 + (t - 40) * 32;             up = 6 + (t - 40) * 1.4
            default:      down = 505 + 10 * sin(t / 1.5);         up = 24 + 1.5 * sin(t / 2)
            }
            return SpeedSample(downMbps: (down * 10).rounded() / 10, upMbps: (up * 10).rounded() / 10)
        }
    }
}
