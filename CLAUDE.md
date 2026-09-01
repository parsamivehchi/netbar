# netbar

NetBar - native SwiftUI menu bar network monitor for the MacBook Air. Shows live
down/up throughput (`↓ 12.4  ↑ 0.8 Mbps`) in the menu bar; the click-open panel shows
Wi-Fi SSID, interface, local IP, router IP, public IP (on-demand only, 5 min cache),
session totals, and a 60 s sparkline. Launch-at-login via SMAppService with an
in-panel toggle. LSUIElement app: no Dock icon, no windows.

## Stack

- SwiftUI + MenuBarExtra (`.window` style), macOS 26+ deployment target
- @Observable view model, actor services, Swift 6 concurrency
- XcodeGen (project.yml -> .xcodeproj; run `xcodegen generate` after adding files)

## Conventions

Follow [iOS conventions](~/.claude/conventions/ios.md).

## Convention Overrides

- Skip: GRDB (no database - live kernel counters only)
- Skip: Keychain (no secrets)

## Build + deploy

```sh
xcodegen generate
xcodebuild -project NetBar.xcodeproj -scheme NetBar -configuration Release -derivedDataPath build build
# Strip com.apple.provenance xattrs BEFORE codesign (battcal lesson) and deploy to a
# STABLE path so TCC location grants + the SMAppService login item survive rebuilds:
ditto --norsrc --noextattr --noacl build/Build/Products/Release/NetBar.app ~/Applications/NetBar.app
codesign --force --deep --sign - ~/Applications/NetBar.app
open ~/Applications/NetBar.app
```

## Hard-won constraints (do not regress)

- Counters come from `sysctl NET_RT_IFLIST2` (64-bit `if_data64`), never `getifaddrs`
  (32-bit counters wrap in ~34 s at 1 Gbps). Walk records with `loadUnaligned`, never
  `load(as:)` - records are packed at `ifm_msglen` strides.
- Count ONLY the primary interface (SCDynamicStore `State:/Network/Global/IPv4` ->
  `PrimaryInterface`). Summing interfaces double-counts VPN traffic (utun + en0).
- The menu bar label is only assigned when the rendered string CHANGES - that gate is
  the redraw control; do not remove it.
- Sampling pauses on `screensDidSleepNotification` and resets the counter baseline on
  wake (otherwise the first delta after wake is hours of traffic in one tick).
- Public IP fetch lives ONLY in PanelView's `.task` (cancelled on close), so a
  background fetch is structurally impossible. Keep it that way.
- SSID needs Location Services (macOS 14+); the panel must show the grant affordance,
  never a blank row. Pattern ported from battcal's WiFiMonitor.
- Ad-hoc signing: each rebuild changes the signature and can invalidate the TCC grant
  and login item. Always deploy via the ditto+codesign recipe above to
  `~/Applications/NetBar.app`, then re-toggle login if needed.

## Efficiency gate (run before claiming "efficient")

Release build, 60-120 s under real traffic, sample `ps -o %cpu=,rss= -p <pid>` every
5 s: avg CPU < 0.5%, RSS < 50 MB.
