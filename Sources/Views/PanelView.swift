import SwiftUI

struct PanelView: View {
    // Plain let, not @Bindable (a SwiftUI macro the CLT toolchain cannot expand);
    // @Observable tracking works through plain properties, and every Binding is built
    // manually.
    let model: AppViewModel

    // Dense layout on purpose (owner ask 2026-09-01): tight paddings, small type.
    private let labelColumn: CGFloat = 60
    private static let mask = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"

    var body: some View {
        let samples = model.ring.ordered
        let stats = RingStats(samples: samples)
        VStack(alignment: .leading, spacing: 8) {
            speedHeader(samples: samples)
            statsLine(stats)
            SparklineView(model: model, samples: samples, peak: max(stats.peakDown, stats.peakUp))
            Divider()
            infoRows
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 264)
        .task { await model.panelOpened() }
    }

    // MARK: - Header

    // Hovering the sparkline swaps the header to that moment's values plus an age hint.
    private func speedHeader(samples: [SpeedSample]) -> some View {
        let hovered: (SpeedSample, Int)? = {
            guard let i = model.hoverIndex, i >= 0, i < samples.count else { return nil }
            return (samples[i], (samples.count - 1 - i) * 2)
        }()
        let shown = hovered?.0 ?? model.current
        return HStack(spacing: 12) {
            speedBlock(arrow: "\u{2193}", mbps: shown.downMbps, tint: .accentColor)
            speedBlock(arrow: "\u{2191}", mbps: shown.upMbps, tint: .secondary)
            Spacer()
            if let (_, age) = hovered {
                Text(age == 0 ? "now" : "-\(age)s")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func speedBlock(arrow: String, mbps: Double, tint: Color) -> some View {
        let r = ScaledRate(mbps: mbps, units: model.units)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(arrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(r.value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text(r.unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func statsLine(_ s: RingStats) -> some View {
        let u = model.units
        return HStack(spacing: 10) {
            statPair("peak", ScaledRate(mbps: s.peakDown, units: u), ScaledRate(mbps: s.peakUp, units: u))
            statPair("avg", ScaledRate(mbps: s.avgDown, units: u), ScaledRate(mbps: s.avgUp, units: u))
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func statPair(_ name: String, _ d: ScaledRate, _ u: ScaledRate) -> some View {
        HStack(spacing: 3) {
            Text(name)
            Text("\u{2193}\(d.compact)")
            Text("\u{2191}\(u.compact)")
        }
    }

    // MARK: - Rows

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            wifiRow
            row("Interface", model.interfaceName, identifying: false)
            row("Local IP", model.localIP, identifying: true)
            row("Router", model.routerIP, identifying: true)
            publicIPRow
            sessionRow
        }
    }

    private func row(_ label: String, _ value: String?, identifying: Bool) -> some View {
        let shown = value.map { identifying && !model.identifiersVisible ? Self.mask : $0 }
        return InfoRow(label: label, value: shown ?? "-", column: labelColumn,
                       copied: model.copiedKey == label, masked: identifying && !model.identifiersVisible) {
            model.copyRow(label: label, value: value, identifying: identifying)
        }
    }

    private var wifiRow: some View {
        HStack(alignment: .firstTextBaseline) {
            rowLabel("Wi-Fi")
            if model.wifi.authorized {
                let ssid = model.wifi.ssid
                let shown = ssid.map { model.identifiersVisible ? $0 : Self.mask } ?? "Not connected"
                copyable(shown, copied: model.copiedKey == "Wi-Fi", masked: !model.identifiersVisible && ssid != nil) {
                    model.copyRow(label: "Wi-Fi", value: ssid, identifying: true)
                }
            } else if model.wifi.auth == .notDetermined {
                Button("Grant access") { model.wifi.requestAuth() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .help("macOS requires Location access to read the Wi-Fi name")
            } else {
                Button("Open Settings") { model.wifi.openLocationSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .help("Location access was denied; enable it to see the Wi-Fi name")
            }
            Spacer(minLength: 0)
            if model.privacyMode {
                Button {
                    model.revealBriefly()
                } label: {
                    Image(systemName: model.identifiersVisible ? "eye" : "eye.slash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.identifiersVisible ? "Rows are shown for a few seconds" : "Show the masked rows for 8 seconds")
            }
        }
    }

    private var publicIPRow: some View {
        HStack(alignment: .firstTextBaseline) {
            rowLabel("Public IP")
            if !model.publicIPLookup {
                Text("off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Public IP lookup is disabled in the footer")
            } else if let ip = model.publicIP {
                copyable(model.identifiersVisible ? ip : Self.mask,
                         copied: model.copiedKey == "Public IP", masked: !model.identifiersVisible) {
                    model.copyRow(label: "Public IP", value: ip, identifying: true)
                }
            } else if model.fetchingPublicIP {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text("-")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var sessionRow: some View {
        HStack(alignment: .firstTextBaseline) {
            rowLabel("Session")
            VStack(alignment: .leading, spacing: 1) {
                Text("\u{2193}\(bytes(model.totalInBytes)) \u{2191}\(bytes(model.totalOutBytes))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("since \(model.sessionStart.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                model.resetSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset session totals and the sparkline")
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: labelColumn, alignment: .leading)
    }

    /// A value that copies itself on click and flashes a checkmark.
    private func copyable(_ text: String, copied: Bool, masked: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(masked ? .secondary : .primary)
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .help(masked ? "Masked by privacy mode" : "Click to copy")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                rowLabel("Bar style")
                segmented(selected: model.barStyle == .stacked ? 0 : 1, labels: ["Stacked", "Wide"]) { i in
                    model.setBarStyle(i == 0 ? .stacked : .wide)
                }
            }
            HStack(spacing: 6) {
                rowLabel("Units")
                segmented(selected: model.units == .bits ? 0 : 1, labels: ["bits/s", "bytes/s"]) { i in
                    model.setUnits(i == 0 ? .bits : .bytes)
                }
            }
            checkbox("Privacy mode (mask name and IPs)", isOn: model.privacyMode) { model.setPrivacyMode($0) }
            checkbox("Look up public IP when panel opens", isOn: model.publicIPLookup) { model.setPublicIPLookup($0) }
            HStack {
                checkbox("Launch at login", isOn: model.loginItem.enabled) { model.loginItem.setEnabled($0) }
                Spacer(minLength: 8)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
                    .font(.system(size: 11))
            }
            if let err = model.loginItem.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func checkbox(_ title: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: set))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.system(size: 11))
            .lineLimit(1)
    }

    /// Segmented control; the headless renderer cannot draw the AppKit Picker, so the
    /// same SwiftUI facsimile is used for the screenshot and the live panel gets the real one.
    @ViewBuilder
    private func segmented(selected: Int, labels: [String], set: @escaping (Int) -> Void) -> some View {
        if DemoFixture.renderPath != nil {
            RenderedSegments(selected: selected, labels: labels)
        } else {
            Picker("", selection: Binding(get: { selected }, set: set)) {
                ForEach(labels.indices, id: \.self) { i in Text(labels[i]).tag(i) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    private func bytes(_ v: UInt64) -> String {
        Int64(clamping: v).formatted(.byteCount(style: .decimal))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let column: CGFloat
    let copied: Bool
    let masked: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: column, alignment: .leading)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(masked ? .secondary : .primary)
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onCopy)
            .help(masked ? "Masked by privacy mode" : "Click to copy")
            Spacer(minLength: 0)
        }
    }
}

/// Static look-alike of the small segmented control, used only by PanelRenderer.
private struct RenderedSegments: View {
    let selected: Int
    let labels: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(i == selected ? Color.white.opacity(0.22) : Color.clear)
                    )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
