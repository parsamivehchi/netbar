import AppKit
import Observation

/// How the menu bar item renders. Persisted in UserDefaults; a stored value outside
/// the known cases is discarded and the default wins (validate, never trust storage).
enum BarStyle: String, CaseIterable {
    case stacked  // two tiny lines, ~35px: "↓12.4" over "↑0.8" (default)
    case wide     // one line, ~95px: "↓12.4 ↑0.8 Mbps"

    static let defaultsKey = "barStyle"
}

@MainActor
@Observable
final class AppViewModel {
    // Menu bar. `label` is the wide one-line text (also the accessibility name);
    // `labelImage` is the stacked two-line render used when barStyle == .stacked.
    private(set) var label = AppViewModel.format(.zero, units: .bits)
    private(set) var labelImage = AppViewModel.renderStacked(
        down: ScaledRate(mbps: 0, units: .bits), up: ScaledRate(mbps: 0, units: .bits), dimDown: true, dimUp: true)
    private(set) var barStyle: BarStyle = {
        guard let raw = UserDefaults.standard.string(forKey: BarStyle.defaultsKey),
              let style = BarStyle(rawValue: raw) else { return .stacked }
        return style
    }()

    private(set) var units: RateUnits = {
        guard let raw = UserDefaults.standard.string(forKey: RateUnits.defaultsKey),
              let u = RateUnits(rawValue: raw) else { return .bits }
        return u
    }()

    func setUnits(_ u: RateUnits) {
        guard u != units else { return }
        units = u
        UserDefaults.standard.set(u.rawValue, forKey: RateUnits.defaultsKey)
        refreshLabel(with: current, force: true)
    }

    // Privacy mode: identifying rows (SSID, local IP, router, public IP) render masked.
    // Persisted; the reveal window is not. Demo renders can force it via NETBAR_DEMO_PRIVACY=1.
    private(set) var privacyMode: Bool =
        DemoFixture.isActive ? DemoFixture.privacy : UserDefaults.standard.bool(forKey: "privacyMode")
    private(set) var revealUntil: Date?
    private var revealTask: Task<Void, Never>?

    func setPrivacyMode(_ on: Bool) {
        guard on != privacyMode else { return }
        privacyMode = on
        revealUntil = nil
        revealTask?.cancel()
        UserDefaults.standard.set(on, forKey: "privacyMode")
    }

    /// True when identifying rows should be shown in clear.
    var identifiersVisible: Bool {
        if !privacyMode { return true }
        if let until = revealUntil { return until > Date() }
        return false
    }

    /// Show the masked rows for a few seconds, then re-mask.
    func revealBriefly(seconds: Double = 8) {
        revealUntil = Date().addingTimeInterval(seconds)
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.revealUntil = nil
        }
    }

    /// Whether the panel may look up the WAN address at all (default on).
    private(set) var publicIPLookup: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "publicIPLookup") == nil ? true : d.bool(forKey: "publicIPLookup")
    }()

    func setPublicIPLookup(_ on: Bool) {
        guard on != publicIPLookup else { return }
        publicIPLookup = on
        UserDefaults.standard.set(on, forKey: "publicIPLookup")
        if !on { publicIP = nil }
    }

    // Click-to-copy feedback: the label of the row copied within the last ~1 s.
    private(set) var copiedKey: String?
    private var copiedTask: Task<Void, Never>?

    /// Copies a row's value; masked rows copy nothing (privacy must not leak via clipboard).
    func copyRow(label: String, value: String?, identifying: Bool) {
        guard let value, !value.isEmpty, !(identifying && !identifiersVisible) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        copiedKey = label
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            if self?.copiedKey == label { self?.copiedKey = nil }
        }
    }

    // Session
    private(set) var sessionStart = Date()

    /// Zero the totals and the sparkline; the next sample starts from a clean baseline.
    func resetSession() {
        totalInBytes = 0
        totalOutBytes = 0
        ring.removeAll()
        sessionStart = Date()
        if !DemoFixture.isActive {
            Task { [sampler] in await sampler.resetBaseline() }
        }
    }

    func setBarStyle(_ style: BarStyle) {
        guard style != barStyle else { return }
        barStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: BarStyle.defaultsKey)
        refreshLabel(with: current, force: true)
    }

    // Live state (observed only while the panel is open)
    private(set) var current = SpeedSample.zero
    private(set) var ring = RingBuffer(capacity: 60)
    private(set) var totalInBytes: UInt64 = 0
    private(set) var totalOutBytes: UInt64 = 0
    private(set) var interfaceName: String?
    private(set) var routerIP: String?
    private(set) var localIP: String?
    private(set) var publicIP: String?
    private(set) var fetchingPublicIP = false

    // Sparkline hover (panel-only state; lives here because @State is a SwiftUI macro
    // the CLT toolchain cannot expand - see CLAUDE.md). nil = not hovering.
    var hoverIndex: Int?

    let wifi: WiFiMonitor
    let loginItem = LoginItemService()

    private let sampler = NetSampler()
    private let publicIPService = PublicIPService()
    private var samplingTask: Task<Void, Never>?
    private var watcherTasks: [Task<Void, Never>] = []

    init() {
        if DemoFixture.isActive {
            // Screenshot mode: synthetic values only, nothing is sampled or fetched.
            wifi = WiFiMonitor(demoSSID: DemoFixture.ssid)
            seedDemo()
            return
        }
        wifi = WiFiMonitor()
        // Start from init, NOT from the label view's .task: a menu bar item collapsed
        // into the notch/overflow chevron never displays its label, so a view-lifecycle
        // start would leave the app sampling nothing (bit on first launch, 2026-09-01).
        start()
    }

    private func seedDemo() {
        barStyle = .stacked  // the shipped default, whatever this Mac has persisted
        for sample in DemoFixture.samples { ring.append(sample) }
        current = DemoFixture.current
        totalInBytes = DemoFixture.totalInBytes
        totalOutBytes = DemoFixture.totalOutBytes
        interfaceName = DemoFixture.interfaceName
        routerIP = DemoFixture.routerIP
        localIP = DemoFixture.localIP
        publicIP = DemoFixture.publicIP
        refreshLabel(with: current, force: true)
    }

    /// Idempotent: the MenuBarExtra label's .task may also call this if the label renders.
    func start() {
        guard !DemoFixture.isActive, watcherTasks.isEmpty else { return }
        startSampling()
        watchDisplaySleep()
    }

    // MARK: - Sampling loop (1 Hz, coalescing-friendly tolerance)

    private func startSampling() {
        samplingTask?.cancel()
        samplingTask = Task { [sampler] in
            await sampler.resetBaseline()
            while !Task.isCancelled {
                let tick = await sampler.sample()
                if Task.isCancelled { break }
                self.apply(tick)
                // 2 s cadence (iStat-class default): halves per-tick label work; the
                // 60-slot ring then spans a 2 min sparkline window.
                try? await Task.sleep(for: .seconds(2), tolerance: .seconds(0.5))
            }
        }
    }

    private func apply(_ tick: NetSampler.Tick) {
        if tick.sample != current { current = tick.sample }
        ring.append(tick.sample)
        totalInBytes &+= tick.deltaInBytes
        totalOutBytes &+= tick.deltaOutBytes
        if tick.interfaceName != interfaceName { interfaceName = tick.interfaceName }
        if tick.router != routerIP { routerIP = tick.router }
        refreshLabel(with: tick.sample, force: false)
    }

    // The redraw gate: only touch the observed label/image when the rendered TEXT
    // changes - assigning either re-renders the menu bar item.
    private func refreshLabel(with sample: SpeedSample, force: Bool) {
        let newLabel = Self.format(sample, units: units)
        let changed = newLabel != label
        if changed { label = newLabel }
        if barStyle == .stacked, changed || force {
            labelImage = stackedImage(down: ScaledRate(mbps: sample.downMbps, units: units),
                                      up: ScaledRate(mbps: sample.upMbps, units: units),
                                      dimDown: sample.downMbps < Self.idleMbps,
                                      dimUp: sample.upMbps < Self.idleMbps)
        }
    }

    /// Below this a line is drawn dimmed: the eye reads "quiet" without parsing a number.
    static let idleMbps = 0.05

    // At idle the label bounces between a handful of states (0.0/0.1 pairs), so a
    // small cache makes most ticks reuse an already-rendered image instead of
    // allocating + drawing a fresh NSImage - that churn measured ~0.6% extra CPU.
    private var imageCache: [String: NSImage] = [:]

    private func stackedImage(down: ScaledRate, up: ScaledRate, dimDown: Bool, dimUp: Bool) -> NSImage {
        let key = "\(down.value)|\(down.unit)|\(up.value)|\(up.unit)|\(dimDown)\(dimUp)"
        if let hit = imageCache[key] { return hit }
        if imageCache.count > 64 { imageCache.removeAll(keepingCapacity: true) }
        let image = Self.renderStacked(down: down, up: up, dimDown: dimDown, dimUp: dimUp)
        imageCache[key] = image
        return image
    }

    /// Two lines drawn into a TEMPLATE image (alpha-only, so the system recolors it for
    /// light/dark menu bars). An image label is the only way to stack two lines -
    /// MenuBarExtra flattens text labels to a single line.
    ///
    /// Layout is three aligned columns so the digits of both lines sit under each other:
    ///   [arrow 7pt][value, right-aligned, 4 figure-space-padded chars][unit 6.5pt, dimmer]
    /// A line under `idleMbps` draws at reduced alpha.
    static func renderStacked(down: ScaledRate, up: ScaledRate, dimDown: Bool, dimUp: Bool) -> NSImage {
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let unitFont = NSFont.systemFont(ofSize: 6.5, weight: .medium)
        let arrowFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
        func attrs(_ font: NSFont, alpha: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(alpha)]
        }
        let arrowW: CGFloat = 7
        let unitW: CGFloat = 12
        let valueW = ceil(NSAttributedString(string: "\u{2007}\u{2007}\u{2007}\u{2007}", attributes: attrs(valueFont, alpha: 1)).size().width)
        let width = arrowW + valueW + 1 + unitW
        let lines: [(arrow: String, rate: ScaledRate, dim: Bool, baseline: CGFloat)] = [
            ("\u{2193}", down, dimDown, 11),
            ("\u{2191}", up, dimUp, 1),
        ]
        let image = NSImage(size: NSSize(width: width, height: 21), flipped: false) { _ in
            for line in lines {
                let a: CGFloat = line.dim ? 0.45 : 1
                NSAttributedString(string: line.arrow, attributes: attrs(arrowFont, alpha: a))
                    .draw(at: NSPoint(x: 0, y: line.baseline))
                let v = NSAttributedString(string: line.rate.padded(), attributes: attrs(valueFont, alpha: a))
                v.draw(at: NSPoint(x: arrowW + valueW - ceil(v.size().width), y: line.baseline))
                NSAttributedString(string: line.rate.unit, attributes: attrs(unitFont, alpha: a * 0.7))
                    .draw(at: NSPoint(x: arrowW + valueW + 1, y: line.baseline + 0.5))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Display sleep: pause sampling (nothing is visible), reset baseline on wake

    private func watchDisplaySleep() {
        let sleeps = workspaceEvents(NSWorkspace.screensDidSleepNotification)
        let wakes = workspaceEvents(NSWorkspace.screensDidWakeNotification)
        watcherTasks.append(Task { [weak self] in
            for await _ in sleeps {
                self?.samplingTask?.cancel()
                self?.samplingTask = nil
            }
        })
        watcherTasks.append(Task { [weak self] in
            for await _ in wakes {
                self?.startSampling()  // resetBaseline inside avoids a giant first delta
            }
        })
    }

    private func workspaceEvents(_ name: Notification.Name) -> AsyncStream<Void> {
        let nc = NSWorkspace.shared.notificationCenter
        return AsyncStream { continuation in
            let token = nc.addObserver(forName: name, object: nil, queue: nil) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in nc.removeObserver(token) }
        }
    }

    // MARK: - Panel-open work (the only place network info + public IP refresh)

    func panelOpened() async {
        guard !DemoFixture.isActive else { return }
        wifi.read()
        loginItem.refresh()
        localIP = interfaceName.flatMap { NetworkInfo.localIPv4(interface: $0) }
        guard publicIPLookup else { return }
        fetchingPublicIP = true
        let ip = await publicIPService.fetch()
        guard !Task.isCancelled else { return }
        if let ip { publicIP = ip }
        fetchingPublicIP = false
    }

    // MARK: - Formatting

    // Compact on purpose (owner ask 2026-09-01): no space after the arrows, single
    // space between groups - menu bar width is scarce on a notched MacBook.
    // Values are padded to a FIXED width with figure spaces (U+2007): a label whose
    // width changes forces a relayout of the entire menu bar on every tick. Units are
    // attached and auto-scaled (v1.2): "\u{2193}12.4Mb \u{2191}812Kb".
    static func format(_ s: SpeedSample, units: RateUnits) -> String {
        let d = ScaledRate(mbps: s.downMbps, units: units)
        let u = ScaledRate(mbps: s.upMbps, units: units)
        return "\u{2193}\(d.padded())\(d.unit) \u{2191}\(u.padded())\(u.unit)"
    }
}
