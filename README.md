# NetBar

**A native SwiftUI menu bar network monitor for macOS.** Live download and upload speed in the
menu bar, and a click-open panel with your Wi-Fi name, interface, local IP, router, public IP,
session totals and a two-minute sparkline you can hover to inspect any moment.

It reads the kernel's own 64-bit interface counters over `sysctl` - no shell-outs, no agents,
no background network calls - and idles at about 0.18% CPU in 17 MB of memory.

![The NetBar panel on sample data](docs/panel.png)

*Screenshot rendered from the app's built-in demo fixture. Every value in it is sample data
(RFC 5737 addresses, a placeholder SSID); NetBar never ships a capture of a live session.*

Download: [mivehchi.app/netbar](https://mivehchi.app/netbar) (free, ~110 KB zip, macOS 26+).

## What it shows

| Surface | Content |
|---|---|
| Menu bar | Stacked two-line item (`↓12.4` over `↑0.8`, about 35 px wide) by default, or a wide one-line `↓12.4 ↑0.8 Mbps` form - pick in the panel |
| Panel header | Current down / up in Mbps; hovering the sparkline swaps in that moment's values and its age |
| Sparkline | 60 samples x 2 s = the last two minutes, down in the accent colour, up in grey |
| Rows | Wi-Fi SSID, primary interface, local IPv4, router, public IP (fetched only while the panel is open, cached 5 min), session totals since launch |
| Footer | Bar style picker, launch-at-login toggle (SMAppService), Quit |

## Install

1. Unzip and move `NetBar.app` to your Applications folder.
2. First open: right-click the app and choose Open. NetBar is not notarized (it is a free,
   locally built tool), so macOS may also ask you to allow it under System Settings >
   Privacy & Security.
3. The Wi-Fi name needs Location access on macOS 14 and later (Apple gates the SSID behind it).
   The panel shows a Grant access link; NetBar uses the permission for nothing else.

## Build from source

No Xcode required - the CommandLineTools `swiftc` is enough:

```sh
./build.sh                       # -> build/NetBar.app (ad-hoc signed)
ditto --norsrc --noextattr --noacl build/NetBar.app ~/Applications/NetBar.app
codesign --force --sign - ~/Applications/NetBar.app
open ~/Applications/NetBar.app
```

`project.yml` is provided for machines with full Xcode (`xcodegen generate`, then build the
NetBar scheme). Deploy to a stable path: ad-hoc signatures change on every rebuild, and the
Location grant and the login item are bound to the signed bundle at its path.

## Demo mode and screenshots

```sh
NETBAR_DEMO=1 build/NetBar.app/Contents/MacOS/NetBar
```

runs the app on the fixed sample values in `Sources/Demo/DemoFixture.swift` - nothing is
sampled, no Location prompt, no public-IP request. Add a path to render the panel headlessly
to a 2x PNG and exit, which is how `docs/panel.png` is produced:

```sh
NETBAR_DEMO=1 NETBAR_RENDER_PANEL="$PWD/docs/panel.png" build/NetBar.app/Contents/MacOS/NetBar
```

Use these for any screenshot you publish. A capture of a live session carries your real
network name and addresses.

## How it works

- **Counters**: `sysctl NET_RT_IFLIST2` with 64-bit `if_data64` records (32-bit `getifaddrs`
  counters wrap in about 34 s at 1 Gbps), read every 2 s.
- **One interface**: only the primary interface from `SCDynamicStore`
  (`State:/Network/Global/IPv4`), so VPN traffic is not double-counted across `utun` and `en0`.
- **Sleep aware**: sampling pauses when the displays sleep and the baseline resets on wake, so
  the first tick after wake is not hours of traffic at once.
- **Menu bar cost**: the label is fixed-width (figure-space padded, monospaced digits) and only
  reassigned when its text changes; the stacked style is a cached template `NSImage`, because
  `MenuBarExtra` flattens text labels to a single line.
- **Public IP**: fetched from `api.ipify.org` only while the panel is open, never in the
  background.

Measured on a release build with the panel closed: 0.18% average CPU over 60 s (`ps -o cputime`
delta) and 17 MB (`footprint`).

## Requirements

macOS 26 or later, Apple silicon. Swift 6, SwiftUI `MenuBarExtra`, `@Observable`.

## License

[PolyForm Noncommercial 1.0.0](LICENSE) - free for personal and other noncommercial use.
Commercial use needs a license; see [COMMERCIAL.md](COMMERCIAL.md).
