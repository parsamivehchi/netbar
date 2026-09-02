import AppKit
import CoreWLAN
import CoreLocation
import Observation

/// macOS 14+ gates the Wi-Fi SSID behind Location Services, so this owns a CLLocationManager
/// purely to unlock CoreWLAN's ssid() read. It never tracks location beyond that.
/// (Pattern ported from battcal's WiFiMonitor, translated to @Observable and stripped of
/// its home-gate machinery.)
@MainActor
@Observable
final class WiFiMonitor: NSObject {
    private(set) var ssid: String?
    private(set) var auth: CLAuthorizationStatus = .notDetermined

    /// Radio details, refreshed only while the panel is open (readRadio()).
    struct Radio: Equatable {
        var rssi: Int          // dBm
        var noise: Int         // dBm
        var txRateMbps: Double
        var band: String       // "2.4 GHz" / "5 GHz" / "6 GHz"
        var channel: Int
        var phyMode: String    // "Wi-Fi 6E" etc.

        /// 0...4 bars from RSSI (Apple's own thresholds are close to these).
        var bars: Int {
            switch rssi {
            case ..<(-80): return 1
            case ..<(-70): return 2
            case ..<(-60): return 3
            default: return 4
            }
        }
    }
    private(set) var radio: Radio?

    private let cw = CWWiFiClient.shared()
    private let loc = CLLocationManager()
    private let demo: Bool

    /// Demo mode: a fixed SSID, no Location prompt, no CoreWLAN monitoring.
    init(demoSSID: String) {
        demo = true
        super.init()
        ssid = demoSSID
        auth = .authorized
    }

    override init() {
        demo = false
        super.init()
        loc.delegate = self
        auth = loc.authorizationStatus
        if auth == .notDetermined {
            loc.requestWhenInUseAuthorization()
        }
        cw.delegate = self
        try? cw.startMonitoringEvent(with: .ssidDidChange)
        read()
    }

    var authorized: Bool { auth == .authorized || auth == .authorizedAlways }

    /// Ask for Location again (a "Grant access" button when the user deferred the prompt).
    func requestAuth() { loc.requestWhenInUseAuthorization() }

    /// Open System Settings > Privacy > Location Services after a denial.
    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func read() {
        if demo { return }
        let s = cw.interface()?.ssid()
        if s != ssid { ssid = s }
    }

    /// One CoreWLAN query set; call from panelOpened, never from the sampler.
    func readRadio() {
        if demo { return }
        guard let i = cw.interface(), i.ssid() != nil else { radio = nil; return }
        let band: String = {
            switch i.wlanChannel()?.channelBand {
            case .band2GHz: return "2.4 GHz"
            case .band5GHz: return "5 GHz"
            case .band6GHz: return "6 GHz"
            default: return ""
            }
        }()
        let phy: String = {
            switch i.activePHYMode() {
            case .mode11n: return "Wi-Fi 4"
            case .mode11ac: return "Wi-Fi 5"
            case .mode11ax: return "Wi-Fi 6"
            case .mode11be: return "Wi-Fi 7"
            default: return ""
            }
        }()
        let r = Radio(rssi: i.rssiValue(), noise: i.noiseMeasurement(), txRateMbps: i.transmitRate(),
                      band: band, channel: i.wlanChannel()?.channelNumber ?? 0, phyMode: phy)
        if r != radio { radio = r }
    }

    /// Demo mode seeds a plausible radio.
    func seedDemo(_ r: Radio) { radio = r }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.auth = status
            self.read()
        }
    }
}

extension WiFiMonitor: CWEventDelegate {
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.read() }
    }
}
