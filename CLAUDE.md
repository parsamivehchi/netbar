# netbar - native SwiftUI menu bar network monitor for macOS

## What it is

LSUIElement app (no Dock icon): live down/up throughput in the menu bar (stacked two-line
default, wide one-line optional) and a click-open panel (SSID, interface, local/router/public
IP, session totals, 2 min sparkline). SwiftUI `MenuBarExtra` (`.window`), macOS 26+, Swift 6,
plain `swiftc` build, no Xcode. Public repo, pinned. Product page: mivehchi.app/netbar
(repo `domains/mivehchi.app`, Cloudflare Workers). Product copy: README.md.

## Current state (as of 2026-10-22)

- Version 1.4.1 (Info.plist `CFBundleShortVersionString`); HEAD "v1.4.1: refresh Local IP when the counted interface changes" (#8). v1.4.1 behaviour: Local IP and Wi-Fi radio refresh on an interface change while the panel is open.
- Product page already shows v1.4.1 (page.tsx checked 2026-10-22).
- Open (owner): hands-on check of the live Interface picker, Dishy and Dashboard links (per `.claude/STATE.md`).
- Open (owner): decision on the Starlink dashboard seed line (`defaults write` of `starlinkDashboardURL`) living in the public repo docs (per `.claude/STATE.md`; the text is kept in docs/DESIGN-NOTES.md).

## Run, gate, deploy

No dev server, so no `.localhost` name.

```sh
./build.sh   # swiftc -parse-as-library + hand-rolled bundle + ad-hoc codesign
# Deploy to a STABLE path so TCC location grants + the SMAppService login item
# survive rebuilds (ditto strips com.apple.provenance xattrs - battcal lesson):
ditto --norsrc --noextattr --noacl build/NetBar.app ~/Applications/NetBar.app
codesign --force --sign - ~/Applications/NetBar.app
open ~/Applications/NetBar.app
```

`project.yml` is for machines with full Xcode (`xcodegen generate` + xcodebuild); Xcode lives on the MBP only, see `~/.claude/rules/xcode-on-mbp.md`. `./build.sh` is canonical.

- Performance gate (release build, panel CLOSED, no AX polling): `ps -o cputime= -p <pid>` delta over 60 s < 0.30 s; `footprint -p <pid>` < 50 MB; run `networkQuality` and watch the label track its down/uplink. Per-release numbers: docs/DESIGN-NOTES.md.
- Release (the zip is a VENDORED BINARY on the page, no drift gate): `./build.sh`, `ditto -c -k --keepParent build/NetBar.app NetBar.zip`, replace `domains/mivehchi.app/public/downloads/NetBar.zip`, bump version + size strings in `domains/mivehchi.app/app/(app)/netbar/page.tsx` (button label and meta line), `npm run gate` + auto-ship + `npm run deploy` there, verify the zip byte-count live. Panel visual change: regenerate the three renders from the DEMO FIXTURE (`NETBAR_DEMO=1 NETBAR_RENDER_PANEL=... `, `NETBAR_DEMO_PRIVACY=1`, `NETBAR_RENDER_LABEL`), copy to `domains/mivehchi.app/public/netbar/`. Full steps: docs/DESIGN-NOTES.md.
- Public repo: `pii-scan.sh . --images` green in BOTH repos before release; PR path only. `progress/` and `.claude/` are gitignored on purpose.

## Architecture map

- `Sources/App.swift`, `Models/`, `Services/` (actors), `ViewModels/`, `Views/`, `Demo/` (DemoFixture for renders).
- Sampling: `NetSampler` reads `sysctl NET_RT_IFLIST2` counters; `AppViewModel` (@Observable) owns the engine and the NSImage label cache; `ScaledRate` in `Models/RateFormat.swift` formats every rate.
- Panel data: `NetworkInfo`, `WiFiMonitor`, `LinkInfo`, `StarlinkProbe` (panel-open only).

## Invariants

- CLT cannot expand SwiftUI macros on the macOS 27 SDK: no `@State`/`@Bindable`; use a lazy `@MainActor let` global model and manual `Binding(get:set:)`. `@Observable` works.
- Start the engine from `AppViewModel.init`, never a view's `.task` (notch-collapsed items never show their label).
- Counters from `sysctl NET_RT_IFLIST2` (64-bit), never `getifaddrs`; walk records with `loadUnaligned`.
- Count ONE interface, never a sum (VPN double-count); a pinned override resolves its index once.
- Label is fixed-width (figure-space padded), 2 s base cadence, assign only on change; do not return to 1 s ticks.
- The stacked style MUST be a cached template-NSImage label; do not remove the cache.
- Public IP fetch lives ONLY in PanelView `.task`; honour `publicIPLookup` before every fetch. Starlink probe and radio details run only from `panelOpened`.
- Every rate becomes text only via `ScaledRate`.
- Privacy mode must not leak through the clipboard (`copyRow` refuses masked rows).
- Any new AppKit-backed control needs a SwiftUI stand-in for `NETBAR_RENDER_PANEL` renders.
- Pause sampling on screen sleep and reset the baseline on wake.

## Project conventions

Follows [iOS conventions](~/.claude/conventions/ios.md); skips GRDB (no database), Keychain (no secrets), XcodeGen as primary build. Stack: @Observable view model, actor services, Swift 6 concurrency.

## Gotchas

- Ad-hoc signing: each rebuild can invalidate the TCC grant and login item; always deploy via the ditto+codesign recipe, re-toggle login if needed. SSID needs a Location grant; the panel must show the grant affordance.
- macOS 27 status items are not CGWindowList windows: probe the label via AX (`osascript ... get name of menu bar item 1 of menu bar 2`); capture the panel by CG window id with `screencapture -l`. AX click toggles the panel. Full recipe: docs/DESIGN-NOTES.md.

## Where history lives

docs/DESIGN-NOTES.md (full constraint text, release steps, efficiency numbers), `.claude/STATE.md`, `progress/` and `.claude/archives/` (local, gitignored), README.md, git log.
