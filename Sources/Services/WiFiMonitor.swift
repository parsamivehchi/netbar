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
