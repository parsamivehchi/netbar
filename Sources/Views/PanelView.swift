import SwiftUI

struct PanelView: View {
    // Plain let, not @Bindable (a SwiftUI macro the CLT toolchain cannot expand);
    // @Observable tracking works through plain properties, and the one Binding
    // (login toggle) is built manually.
    let model: AppViewModel

    // Dense layout on purpose (owner ask 2026-09-01): tight paddings, small type.
    private let labelColumn: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            speedHeader
            SparklineView(samples: model.ring.ordered)
            Divider()
            infoRows
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 248)
        .task { await model.panelOpened() }
    }

    private var speedHeader: some View {
        HStack(spacing: 12) {
            speedBlock(arrow: "\u{2193}", value: model.current.downMbps, tint: .accentColor)
            speedBlock(arrow: "\u{2191}", value: model.current.upMbps, tint: .secondary)
            Spacer()
        }
    }

    private func speedBlock(arrow: String, value: Double, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(arrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(String(format: "%.1f", value))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text("Mbps")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            wifiRow
            InfoRow(label: "Interface", value: model.interfaceName ?? "-", column: labelColumn)
            InfoRow(label: "Local IP", value: model.localIP ?? "-", column: labelColumn)
            InfoRow(label: "Router", value: model.routerIP ?? "-", column: labelColumn)
            publicIPRow
            InfoRow(label: "Session",
                    value: "\u{2193}\(bytes(model.totalInBytes)) \u{2191}\(bytes(model.totalOutBytes))",
                    column: labelColumn)
        }
    }

    private var wifiRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Wi-Fi")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: labelColumn, alignment: .leading)
            if model.wifi.authorized {
                Text(model.wifi.ssid ?? "Not connected")
                    .font(.system(size: 11, weight: .medium))
                    .textSelection(.enabled)
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
        }
    }

    private var publicIPRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Public IP")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: labelColumn, alignment: .leading)
            if let ip = model.publicIP {
                Text(ip)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .textSelection(.enabled)
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginItem.enabled },
                    set: { model.loginItem.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 11))
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

    private func bytes(_ v: UInt64) -> String {
        Int64(clamping: v).formatted(.byteCount(style: .decimal))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let column: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: column, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
