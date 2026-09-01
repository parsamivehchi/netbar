import AppKit
import Observation

@MainActor
@Observable
final class AppViewModel {
    // Menu bar
    private(set) var label = "\u{2193}0.0 \u{2191}0.0 Mbps"

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

    let wifi = WiFiMonitor()
    let loginItem = LoginItemService()

    private let sampler = NetSampler()
    private let publicIPService = PublicIPService()
    private var samplingTask: Task<Void, Never>?
    private var watcherTasks: [Task<Void, Never>] = []

    init() {
        // Start from init, NOT from the label view's .task: a menu bar item collapsed
        // into the notch/overflow chevron never displays its label, so a view-lifecycle
        // start would leave the app sampling nothing (bit on first launch, 2026-09-01).
        start()
    }

    /// Idempotent: the MenuBarExtra label's .task may also call this if the label renders.
    func start() {
        guard watcherTasks.isEmpty else { return }
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
        // The redraw gate: only touch the observed label when the rendered text changes.
        let newLabel = Self.format(tick.sample)
        if newLabel != label { label = newLabel }
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
        wifi.read()
        loginItem.refresh()
        localIP = interfaceName.flatMap { NetworkInfo.localIPv4(interface: $0) }
        fetchingPublicIP = true
        let ip = await publicIPService.fetch()
        guard !Task.isCancelled else { return }
        if let ip { publicIP = ip }
        fetchingPublicIP = false
    }

    // MARK: - Formatting

    // Compact on purpose (owner ask 2026-09-01): no space after the arrows, single
    // space between groups - menu bar width is scarce on the notched Air.
    // Values are padded to a FIXED width with figure spaces (U+2007): a label whose
    // width changes forces a relayout of the entire menu bar on every tick.
    static func format(_ s: SpeedSample) -> String {
        "\u{2193}\(fmt(s.downMbps)) \u{2191}\(fmt(s.upMbps)) Mbps"
    }

    private static func fmt(_ mbps: Double) -> String {
        let text = mbps >= 999.95 ? String(format: "%.2fG", mbps / 1000)
                                  : String(format: "%.1f", mbps)
        // Pad to 4 chars (stable width across 0-99.9 Mbps, the common band) rather
        // than 5: reserving room for 3-digit speeds at all times wastes bar space.
        let pad = max(0, 4 - text.count)
        return String(repeating: "\u{2007}", count: pad) + text
    }
}
