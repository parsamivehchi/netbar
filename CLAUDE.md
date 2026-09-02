# netbar

NetBar - native SwiftUI menu bar network monitor for macOS (Apple silicon). Shows live
down/up throughput in the menu bar - default is a STACKED two-line ~35px item
(`↓12.4` over `↑0.8`, 9pt); a panel picker switches to the wide one-line
`↓12.4 ↑0.8 Mbps` form (persisted `barStyle` in UserDefaults, validated on read); the
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
- Skip: XcodeGen as the primary build (the dev machine has no Xcode; see build note below)

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
but `./build.sh` is the canonical path: xcodebuild fails on a CommandLineTools-only machine.

## Hard-won constraints (do not regress)

- **CLT cannot expand SwiftUI macros on the macOS 27 SDK.** `@State`/`@Bindable` die
  with "SwiftUIMacros plugin not found". A lazily-initialized `@MainActor let` global
  replaces @State for the app-lifetime model; plain `let` + manual `Binding(get:set:)`
  replaces @Bindable; panel-local UI state (hoverIndex) lives on the @Observable model.
  `@Observable` itself works (libObservationMacros ships with CLT).
- **Start the engine from AppViewModel.init, never a view's .task.** A menu bar item
  collapsed into the notch overflow never displays its label, so a label-lifecycle
  start leaves the app sampling nothing (bit on first launch 2026-09-01).
- **Adaptive cadence (v1.3)**: `cadence` is 2 s while the panel is open or traffic moves,
  4 s after 10 ticks under `quietMbps` (0.5) on both lines, 6 s under Low Power Mode; sleep
  tolerance is cadence/4. `readCounters` is ONE sysctl into the reused buffer, probing the size
  only on ENOMEM. Sub-Mb values quantize to 50 Kb so idle chatter never changes the label.
  Link kind resolves via `LinkInfo.kind(of:)` ONCE per interface name (SCNetworkInterfaceCopyAll
  walks the whole config; never per tick). Radio details (`WiFiMonitor.readRadio`) only in
  `panelOpened`.
- **The menu bar label is fixed-width and 2 s cadence.** Values pad to 4 chars with
  figure spaces (U+2007) + monospacedDigit; a width change forces a bar-wide relayout.
  Together with the assign-only-on-change gate this took closed-panel CPU from 1.15%
  to 0.30% avg. Do not return to 1 s ticks or unpadded values.
- **The stacked style MUST be an NSImage label, and the images MUST be cached.**
  MenuBarExtra flattens its label to one text line (verified macOS 27: a VStack of
  two Texts renders only the first), so stacking requires `Image(nsImage:)` - a
  template image (alpha-only) so the system recolors it per menu bar appearance.
  Allocating a fresh NSImage per tick measured 0.95% CPU / 72 MB; the per-string-pair
  cache in AppViewModel.stackedImage brings it to 0.18% / 17 MB because idle traffic
  bounces between a handful of label states. Do not remove the cache.
- Counters come from `sysctl NET_RT_IFLIST2` (64-bit `if_data64`), never `getifaddrs`
  (32-bit counters wrap in ~34 s at 1 Gbps). Walk records with `loadUnaligned`, never
  `load(as:)` - records are packed at `ifm_msglen` strides.
- Count ONLY the primary interface (SCDynamicStore `State:/Network/Global/IPv4` ->
  `PrimaryInterface`). Summing interfaces double-counts VPN traffic (utun + en0).
- Sampling pauses on `screensDidSleepNotification` and resets the counter baseline on
  wake (otherwise the first delta after wake is hours of traffic in one tick).
- Public IP fetch lives ONLY in PanelView's `.task` (cancelled on close), so a
  background fetch is structurally impossible. Keep it that way. The `publicIPLookup`
  preference (v1.2) can disable it entirely; honour it before every fetch.
- **Units and scaling live in `Models/RateFormat.swift` (v1.2)** - `ScaledRate` is the ONE
  place a rate becomes text (label, wide label, header, stats, sparkline scale). Bits by
  default, bytes via the `units` preference; the label's cache key includes the unit and the
  dim flags. Never format a rate inline in a view.
- **Privacy mode must not leak through the clipboard**: `copyRow` refuses masked identifying
  rows; the reveal window is memory-only. Demo renders force it with `NETBAR_DEMO_PRIVACY=1`.
- SSID needs Location Services (macOS 14+); the panel must show the grant affordance,
  never a blank row. Pattern ported from battcal's WiFiMonitor.
- Ad-hoc signing: each rebuild changes the signature and can invalidate the TCC grant
  and login item. Always deploy via the ditto+codesign recipe above to
  `~/Applications/NetBar.app`, then re-toggle login if needed.
- Verifying the item/label: on macOS 27 status items are NOT app-owned CGWindowList
  windows (MenuBarAgent composites them). Probe via AX:
  `osascript -e 'tell application "System Events" to tell application process "NetBar" to get name of menu bar item 1 of menu bar 2'`
  returns the live label text.

## Distribution (public page - keep in sync on every release)

NetBar is published at https://mivehchi.app/netbar (repo `domains/mivehchi.app`, Cloudflare
Workers). The downloadable zip is a VENDORED BINARY with no drift gate, so a netbar release
does not reach the page by itself. On every release:

1. `./build.sh`, then `ditto -c -k --keepParent build/NetBar.app NetBar.zip`
2. Replace `domains/mivehchi.app/public/downloads/NetBar.zip`
3. Bump the version + size strings in `domains/mivehchi.app/app/(app)/netbar/page.tsx`
   (two places: button label and the meta line) and the Details list if specs changed
4. `npm run gate` there, ship via auto-ship, `npm run deploy`, verify `x-build` == HEAD
   and the zip byte-count at https://mivehchi.app/downloads/NetBar.zip
5. If the panel changed visually: regenerate the three renders from the DEMO FIXTURE, never a
   live capture (`NETBAR_DEMO=1 NETBAR_RENDER_PANEL=$PWD/docs/panel.png ...`, plus
   `NETBAR_DEMO_PRIVACY=1` for `docs/panel-privacy.png` and `NETBAR_RENDER_LABEL` for
   `docs/menubar.png`), copy them to `domains/mivehchi.app/public/netbar/{panel-demo,panel-privacy,menubar}.png`,
   and re-capture the gallery shot. `bash ~/.claude/scripts/pii-scan.sh . --images` must be green in BOTH repos
   (rules/public-demo-privacy.md - the first public shot leaked a real SSID + WAN IP).

## Public repo (since 2026-09-01)

`parsamivehchi/netbar` is PUBLIC and pinned. Nothing machine-specific or personal goes in:
no home paths, no hostnames, no real network values anywhere (code, fixtures, docs, images).
`pii-scan.sh . --images --history` is the gate; the guard blocks a visibility flip without
its stamp. Session archives (`progress/`, `.claude/`) are gitignored on purpose.

## Efficiency gate (run before claiming "efficient")

Release build, panel CLOSED, no AX polling during the window: take a
`ps -o cputime= -p <pid>` DELTA over 60 s (target < 0.30 s = 0.5% avg) and read
memory via `footprint -p <pid>` (target < 50 MB; measured 16 MB). v1.2 (units + dimming +
stats): 0.20 s / 60 s = 0.33% including launch, 16 MB. v1.3 (adaptive cadence, single sysctl,
link row): 0.30 s / 120 s settled = 0.25%, 17 MB, with ~1 Mb/s of real background traffic. ps %cpu decays and
AX queries inflate the target process; `footprint` is the honest memory number, not
ps rss. Throughput correctness: run `networkQuality` and watch the label track its
reported down/uplink (measured: label ↓760 peak vs 654 Mbps downlink).
