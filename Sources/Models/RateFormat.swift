import Foundation

/// Unit family for every rate the app shows. Persisted in UserDefaults; a stored value
/// outside the known cases is discarded and the default wins.
enum RateUnits: String, CaseIterable {
    case bits   // Kb / Mb / Gb per second (what ISPs quote) - default
    case bytes  // KB / MB / GB per second (what download dialogs show)

    static let defaultsKey = "units"
}

/// A rate split into an auto-scaled value and a short unit, so the unit can be drawn
/// smaller than the number. Pure; no allocation beyond the two strings.
struct ScaledRate: Equatable {
    let value: String   // "12.4", "812", "1.02" - never padded here
    let unit: String    // "Kb", "Mb", "Gb" or "KB", "MB", "GB"

    init(mbps: Double, units: RateUnits) {
        let perSecond = units == .bits ? mbps : mbps / 8
        let (k, m, g) = units == .bits ? ("Kb", "Mb", "Gb") : ("KB", "MB", "GB")
        let kilo = perSecond * 1000
        if perSecond >= 999.95 {
            value = String(format: "%.2f", perSecond / 1000); unit = g
        } else if perSecond >= 99.95 {
            value = String(format: "%.0f", perSecond); unit = m
        } else if perSecond >= 0.9995 {
            value = String(format: "%.1f", perSecond); unit = m
        } else {
            value = String(format: "%.0f", kilo); unit = k
        }
    }

    /// Value padded to a fixed width with figure spaces (U+2007) so the menu bar item
    /// never changes width between ticks (a width change relayouts the whole bar).
    func padded(to width: Int = 4) -> String {
        String(repeating: "\u{2007}", count: max(0, width - value.count)) + value
    }

    /// "12.4Mb" - the compact one-line form.
    var compact: String { value + unit }
}

/// Peak and mean over the ring, computed only while the panel is open.
struct RingStats: Equatable {
    let peakDown: Double, peakUp: Double, avgDown: Double, avgUp: Double

    init(samples: [SpeedSample]) {
        guard !samples.isEmpty else { peakDown = 0; peakUp = 0; avgDown = 0; avgUp = 0; return }
        var pd = 0.0, pu = 0.0, sd = 0.0, su = 0.0
        for s in samples {
            pd = max(pd, s.downMbps); pu = max(pu, s.upMbps)
            sd += s.downMbps; su += s.upMbps
        }
        peakDown = pd; peakUp = pu
        avgDown = sd / Double(samples.count); avgUp = su / Double(samples.count)
    }
}
