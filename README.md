# MacFans

Fan control and temperature monitoring for Apple Silicon MacBooks, in the spirit of
Macs Fan Control, built for macOS 26+ with the Liquid Glass design language.

Per-fan curves driven by any combination of sensors, live charts, and the full SMC
sensor list.

## How it is put together

The privileged part and the interface are separate programs:

| Target | What it is | Runs as |
|---|---|---|
| `CSMC` | Raw SMC access over IOKit. No policy. | — |
| `FanKit` | Curves, aggregation, config, wire protocol. No I/O, fully unit-tested. | — |
| `fanctld` | Control loop, safety watchdog, socket server. | root, via launchd |
| `MacFans` | SwiftUI app: menu bar item and window. | you |

They talk over a unix socket at `/var/run/macfans.sock` in newline-delimited JSON.
The app holds no privileges and can be quit or crash at any time; the fans keep being
managed. The transport is behind one protocol type, so moving to XPC and a signed
`SMAppService` helper later does not touch the engine.

## Requirements

- Apple Silicon Mac, macOS 26 or newer
- Xcode (for the SDK) and the Swift toolchain

## Install

```sh
./Scripts/install.sh
```

It builds, proves on your own hardware that a fan responds to a forced target, and
only then installs the daemon. It also stops Macs Fan Control's privileged helper if
it is running, because both would write the same SMC keys.

Build and run the app:

```sh
./Scripts/build-app.sh
open MacFans.app
```

Remove everything:

```sh
./Scripts/uninstall.sh
```

## Safety

- Fans return to system control on exit, on `SIGTERM`/`SIGINT`, and when a fan is
  switched back to auto.
- Any forced state left behind by another process is cleared at startup.
- A watchdog releases every fan if the control loop stops ticking.
- Targets are always clamped to the fan's own `Mn`/`Mx` limits.
- Above the emergency threshold the curve is abandoned and the fan goes to full speed.
- Settings, Release all fans hands everything back at once.

## What was measured on this hardware

Checked on a MacBook Pro 18,2 (M1 Max) running macOS 27.0, not assumed:

- 2 fans, `F0*`/`F1*`, ranges 1499-5348 and 1499-5776 rpm.
- SMC reads work unprivileged; writes return `kIOReturnNotPrivileged` without root.
- 2251 SMC keys, 228 of them temperatures.
- `flt` is a little-endian IEEE float; `ioft` is 64-bit little-endian fixed point with
  16 fractional bits; the integer types are big-endian.
- The fans stop completely (0 rpm) when the machine is cool, which is below the SMC's
  own reported minimum of 1499 rpm. A curve therefore makes an idle machine *louder*
  than auto unless you want the floor.
- `F0Md` is not a plain "forced" flag: a value of 3 was observed while another fan
  utility was installed. Ownership is tracked in the daemon, never inferred from it.

## Development

```sh
swift test                 # FanKit logic, no hardware needed
./.build/debug/fanctld --probe     # read-only hardware dump, no root
sudo fanctld --selftest            # proves a fan responds, then restores auto
MACFANS_SOCKET=/tmp/macfans-dev.sock fanctld --dev   # unprivileged, for UI work
```
