# netbar

NetBar - native SwiftUI menu bar network monitor for the MacBook Air. Shows live
down/up throughput (`↓12.4 ↑0.8 Mbps`, compact fixed-width) in the menu bar; the
click-open panel shows Wi-Fi SSID, interface, local IP, router IP, public IP
(on-demand only, 5 min cache), session totals, and a 2 min sparkline (60 slots x 2 s)
with hover inspection (crosshair + the header swaps to the hovered moment's values).
Launch-at-login via SMAppService with an in-panel toggle. LSUIElement app: no Dock
icon, no windows.

## Stack

- SwiftUI + MenuBarExtra (`.window` style), macOS 26+ deployment target
- @Observable view model, actor services, Swift 6 concurrency
- Built with plain `swiftc` (CommandLineTools) via `./build.sh` - no Xcode required

## Conventions

Follow [iOS conventions](~/.claude/conventions/ios.md).

## Convention Overrides

- Skip: GRDB (no database - live kernel counters only)
- Skip: Keychain (no secrets)
- Skip: XcodeGen as the primary build (the Air has no Xcode; see build note below)

## Build + deploy

```sh
./build.sh   # swiftc -parse-as-library + hand-rolled bundle + ad-hoc codesign
# Deploy to a STABLE path so TCC location grants + the SMAppService login item
# survive rebuilds (ditto strips com.apple.provenance xattrs - battcal lesson):
ditto --norsrc --noextattr --noacl build/NetBar.app ~/Applications/NetBar.app
codesign --force --sign - ~/Applications/NetBar.app
open ~/Applications/NetBar.app
```

`project.yml` is kept for machines WITH full Xcode (`xcodegen generate` + xcodebuild),
but `./build.sh` is the canonical path: this machine's xcodebuild fails without Xcode.

## Hard-won constraints (do not regress)

- **CLT cannot expand SwiftUI macros on the macOS 27 SDK.** `@State`/`@Bindable` die
  with "SwiftUIMacros plugin not found". A lazily-initialized `@MainActor let` global
  replaces @State for the app-lifetime model; plain `let` + manual `Binding(get:set:)`
  replaces @Bindable; panel-local UI state (hoverIndex) lives on the @Observable model.
  `@Observable` itself works (libObservationMacros ships with CLT).
- **Start the engine from AppViewModel.init, never a view's .task.** A menu bar item
  collapsed into the notch overflow never displays its label, so a label-lifecycle
  start leaves the app sampling nothing (bit on first launch 2026-09-01).
- **The menu bar label is fixed-width and 2 s cadence.** Values pad to 4 chars with
  figure spaces (U+2007) + monospacedDigit; a width change forces a bar-wide relayout.
  Together with the assign-only-on-change gate this took closed-panel CPU from 1.15%
  to 0.30% avg. Do not return to 1 s ticks or unpadded values.
- Counters come from `sysctl NET_RT_IFLIST2` (64-bit `if_data64`), never `getifaddrs`
  (32-bit counters wrap in ~34 s at 1 Gbps). Walk records with `loadUnaligned`, never
  `load(as:)` - records are packed at `ifm_msglen` strides.
- Count ONLY the primary interface (SCDynamicStore `State:/Network/Global/IPv4` ->
  `PrimaryInterface`). Summing interfaces double-counts VPN traffic (utun + en0).
- Sampling pauses on `screensDidSleepNotification` and resets the counter baseline on
  wake (otherwise the first delta after wake is hours of traffic in one tick).
- Public IP fetch lives ONLY in PanelView's `.task` (cancelled on close), so a
  background fetch is structurally impossible. Keep it that way.
- SSID needs Location Services (macOS 14+); the panel must show the grant affordance,
  never a blank row. Pattern ported from battcal's WiFiMonitor.
- Ad-hoc signing: each rebuild changes the signature and can invalidate the TCC grant
  and login item. Always deploy via the ditto+codesign recipe above to
  `~/Applications/NetBar.app`, then re-toggle login if needed.
- Verifying the item/label: on macOS 27 status items are NOT app-owned CGWindowList
  windows (MenuBarAgent composites them). Probe via AX:
  `osascript -e 'tell application "System Events" to tell application process "NetBar" to get name of menu bar item 1 of menu bar 2'`
  returns the live label text.

## Efficiency gate (run before claiming "efficient")

Release build, panel CLOSED, no AX polling during the window: take a
`ps -o cputime= -p <pid>` DELTA over 60 s (target < 0.30 s = 0.5% avg) and read
memory via `footprint -p <pid>` (target < 50 MB; measured 16 MB). ps %cpu decays and
AX queries inflate the target process; `footprint` is the honest memory number, not
ps rss. Throughput correctness: run `networkQuality` and watch the label track its
reported down/uplink (measured: label ↓760 peak vs 654 Mbps downlink).
