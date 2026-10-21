# US16x08Panel — unofficial native (Apple Silicon) panel for the TASCAM US-16x08

A from-scratch Swift replacement for TASCAM's Intel-only Settings Panel.
Uses the USB control protocol documented by the Linux kernel driver
(`sound/usb/mixer_us16x08.c`, © 2016 Detlef Urban, GPL-2.0-or-later).
Because the protocol knowledge comes from that GPL code, treat this project as
GPL-2.0-or-later if you redistribute it.

**Status: first draft, written without access to macOS or the hardware.**
The protocol layer is checked against golden vectors; everything that touches
USB or SwiftUI is untested until you run it.

Open bugs and the backlog are tracked in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Documentation
Start at [docs/README.md](docs/README.md) (tutorial, how-to guides, reference, explanation).

## Layout
| Target | What it is |
|---|---|
| `CUSB` | ~150-line C shim over IOKit `IOUSBDeviceInterface942` (same mechanism the original app uses) |
| `US16x08Core` | Protocol builders, state model, `DeviceLink` (coalescing + meter polling), transports |
| `us16x08ctl` | CLI for bring-up + guided hardware self-test |
| `US16x08Panel` | SwiftUI app, laid out after the original panel in a macOS 27 (Golden Gate) style: toolbar tabs (Mixer, Routing, Interface, Scenes) with a title-bar status chip, **docked EQ/Compressor panel above the strips** (draggable curve nodes), 16 strips + master, Routing flow diagram, Log |

## Prerequisites (one-time setup)
You need **full Xcode**, not just the Command Line Tools. `swift test` needs XCTest and the
macOS SDK frameworks, which only ship with Xcode. Symptoms of the wrong setup:
`unable to resolve module dependency: 'XCTest'` and linker warnings mentioning
`/Library/Developer/CommandLineTools`.

1. Install Xcode (App Store or developer.apple.com) and **open it once** so it installs its additional components.
2. Point the command-line tools at it (adjust the path if your copy is named differently, e.g. `Xcode-beta.app`):
   ```
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
3. Accept the licence and finish first-launch setup:
   ```
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   ```
4. Check it took:
   ```
   xcode-select -p        # -> /Applications/Xcode.app/Contents/Developer
   swift --version        # -> Apple Swift 5.9 or newer, target arm64-apple-macosx
   xcrun --find xctest    # -> a path inside Xcode.app
   ```
   (To try Xcode for one shell only, without `sudo`: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.)

After a clean rebuild (`rm -rf .build`) the `ld: warning: search path '/Library/Developer/CommandLineTools/...' not found` lines should be gone.
You can also run `xed .` to open the package in Xcode (test navigator, debugger, signing).

## UI notes
- Compact window (about the size of TASCAM's panel; default 1100×650, minimum 1000×~570, all derived from `Layout.swift`). Built from standard SwiftUI components (`.toolbar`, segmented `Picker`, `Menu`, `Toggle`) so Golden Gate's window corners, toolbar and the user's Liquid Glass slider apply automatically. Content surfaces (strips, curves) are opaque; no custom glass.
- Selecting a strip drives the docked DSP panel. EQ/COMP chips on a strip toggle that block; every EQ/compressor value has a knob and an editable number box; drag the nodes on the curves. Closing the window quits the app. Full guide: [docs/](docs/README.md).
- EQ frequencies are real Hz from the device's table; the curve is a filter model. Both charts have labelled logarithmic-frequency / dB scales.
- Shown but disabled until their protocol is captured: Solo, Link.
- Interface screen shows what macOS can tell us (USB descriptor via IORegistry, sample rate via Core Audio). Scenes: 10 named slots stored on this Mac (`scenes.json`); recalling sends everything to the unit. Toolbar has a quick-recall menu. `us16x08ctl info` prints the same device facts.
- **Firmware version**: the USB `bcdDevice` is NOT the firmware version (it reads 1.00 on a v2.00 unit). The real value comes from the unit's own query, reverse-engineered from the original panel (`usctl_get_version`): send `31 01 00 00` (vendor OUT 0x1D), read vendor IN 0x1E frames, take tags 0x32 (version, decimal x100: 200 = V2.00) / 0x33 (build), each a little-endian u16; text tags 0x34 (product), 0x35 (build date), 0x36 (build time) arrive in the same reply. Confirmed on a real V2.00 unit (`swift run us16x08ctl firmware`).
- Channel DSP menu: Copy / Paste / Reset between channels.
- Appearance (Auto / Light / Dark) is in the toolbar and remembered between launches; Auto follows the system.

## Test plan — do these in order (safest first)
Quit TASCAM's original panel first (two clients on one device).

1. `swift test` — protocol vs. golden vectors (XCTest). No hardware.
2. `swift run us16x08ctl list` — expect a line `0644:8047 ...`.
3. `swift run us16x08ctl probe` — **read-only**: sends the 4-byte meter-init message and reads one 64-byte frame. PASS means the USB path and protocol handshake work.
4. `swift run us16x08ctl meters 10` — talk into an input; numbers should move.
5. `swift run us16x08ctl selftest` — guided; changes one control at a time, asks what you heard, restores it, and writes `us16x08-selftest-report.txt`. **Paste that report back.**
6. `swift run US16x08Panel` — the GUI (auto-connects; "Dry-run" button runs without sending).
7. `./Scripts/make_app.sh` — builds `build/US16x08 Panel.app` and prints `Architectures: arm64`.

`--dry-run` works on every CLI command and prints the exact bytes instead of sending.

## Things I'm unsure about (the self-test targets these)
- **USB access path**: whether EP0 requests work without opening the device on your macOS version. The shim retries with a non-seizing open if the OS asks. Errors print a decoded IOReturn.
- **High-band EQ frequency**: the Linux driver sends the raw value; the device's own default (0x2f) suggests a +0x20 offset, which I apply. Compare with `--kernel-high-freq`.
- **Compressor ratio labels** (`ratio × 10`, last = max) are now exact (see below). Solo, Link, channel names and scene memory are not in the Linux driver and are not implemented yet.
- The device **cannot be read back**; the app stores what it last sent (`~/Library/Application Support/US16x08Panel/state.json`) and pushes all of it to the unit on every connect.

## Not in scope
Firmware updating (use TASCAM's tool; a bad flash can brick the unit), scenes, the Interface page.

## Naming notes (confirmed from the original panel's code)
- **Mixer True Bypass** = message `45 02 <0|1>` (our `bypass`). **Computer out to Stereo BUS** = message `44 02 <0|1>` (our `bussOut`); ON is the normal state, v2.10 added the OFF choice.
- Interface page text format matches the original: "Firmware Version 2.00 0022" = version, then build padded to 4 digits.

## Automated audio test (`us16x08ctl autotest`)
The Mac plays 1 kHz tones into the unit over USB and the unit's own level meters report the result, so every
check is measured pass/fail (no microphone permission needed). **It plays audio** — turn monitors/headphones down.
- **Stage 1, no cables:** USB out 1/2 -> Computer out to Stereo Bus -> master meters. Checks odd->L / even->R, master mute, master fader, Computer-out-to-Stereo-BUS OFF, and records the effect of Mixer True Bypass.
- **Stage 2, one cable (LINE OUT 8 -> LINE IN 16):** the tone returns as input 16. Checks channel mute/fader/pan, EQ up/down/off, compressor (level + GR meter) and routing. Skipped automatically if no loopback is detected.
- Options: `--level=-30` (dBFS, default -24; stage 2 adds 12 dB), `--yes` (skip the prompt). Writes `us16x08-autotest-report.txt`.
- Not measurable this way: phase invert, EQ frequency accuracy, Solo/Link (not implemented).

## Hot-plug
The app watches USB with IOKit notifications: unplugging updates the status pane immediately, plugging back in reconnects (the full remembered state is then resent automatically, since the unit cannot be read back).

## Meter calibration (confirmed on hardware)
From the automated test on a real US-16x08: level meters are **linear amplitude, 0x7FFF = digital full scale** (a -24 dBFS tone reads -23.7 dBFS;
channel/master fader steps read within 0.3 dB). The **compressor meter is the applied linear gain x 0x7FFF** (raw 1740 = 25.5 dB of reduction while the
output measurably dropped 25.3 dB), not the amount of reduction. Centre pan is -3.0 dB per side. With every input open the master meters idle around
-52 dBFS (raw ~82); the input meters idle near raw 1.

## Meters, peaks and clip
- Meters start automatically when the unit connects (after the firmware query) and again after a re-plug; there is no on/off switch.
- Each meter has a **peak-hold line** (held 1.5 s, then falls 20 dB/s) and a **clip segment** at the top that latches red when the level reaches 32700 (about -0.02 dBFS; a clipping input read 32765 on real hardware). Click the red segment to clear it, or use "Clear peaks" on the master strip. Hover a meter for its peak in dBFS.
- Polling now rides out brief USB errors and only stops (with a log entry) after about half a second of continuous failure.
- Switches that live on the unit (Mixer True Bypass, Computer out to Stereo BUS) are disabled while it is disconnected; faders, EQ and so on stay editable offline so scenes can be prepared and are sent on connect.

## EQ and compressor scales (read from the original panel, checked against the manual)
- **Frequencies:** one 64-entry device scale (32 Hz - 18 kHz). LOW uses steps 0-31 (32 Hz - 1.6 kHz), the mids 0-63, HIGH the top half (1.7 - 18 kHz), which is why HIGH carries the +0x20 wire offset. All four manual defaults (80 Hz / 300 Hz / 1.2 kHz / 5.0 kHz) land on the device default steps. 16 kHz and 17 kHz in the mid table are inferred from the HIGH table.
- **Q:** width steps 0-6 = 0.25, 0.5, 1, 2, 4, 8, 16 (default 1.00).
- **Compressor (Reference Manual ranges, confirmed against the original panel):** threshold -32...0 dB (default 0), ratio 1.0:1 ... 16.0:1 and ∞:1 (default 1.0:1), make-up gain 0-20 dB (default 0), attack 2-200 ms in 2 ms steps (default 2), release 10-1000 ms in 10 ms steps (default 10). Held in `CompressorSettings` and pinned by tests. The graph uses the original panel's -48...0 dB axes and includes make-up gain.
- The EQ curve now draws RBJ shelf and bell filters at 44.1 kHz from these values. It is a close visual model, not a copy of the unit's DSP.

## Input groups
1-8 are XLR mic inputs, 9-10 are front jack inputs switchable between line and instrument, 11-16 are line inputs on the back. Gain for 1-10 is set with knobs on the unit, so there is no gain control in software. The mixer labels the groups, and the autotest loopback deliberately uses input 16 (a line input).

## Diagnostics and About
- **Diagnostics Log** is its own window: Window menu > Diagnostics Log (Option-Command-L). It shows everything sent to the unit and every error, with Copy All and Save for bug reports.
- **About** (app menu) carries the credits, the "unofficial, not affiliated" statement, the GPL notice and links to the Linux driver this builds on.

## Licence and attribution
GPL-2.0-or-later, as a derivative work of the Linux US-16x08 mixer driver by Detlef Urban. See `NOTICE.md` for the full attribution and links, and `COPYING` for the licence (run `Scripts/fetch_license.sh` once to install the full text before distributing). Every source file has an SPDX header.

## App icon
`Resources/AppIcon.icns` is built into the app by `Scripts/make_app.sh`. It follows Apple's macOS template (1024 px canvas, 824 px
squircle body, shadow in the margin) and is an homage to the "bio-cell" side panels of the original panel: a brushed-metal bezel around
rounded black cells. Regenerate everything with `python3 tools/make_icon.py [seed]` (needs numpy, scipy, Pillow; seed 7 is the shipped
layout). `Resources/AppIcon.iconset/` can be turned into an `.icns` on a Mac with `iconutil -c icns Resources/AppIcon.iconset`.
Sizes of 64 px and below use simplified art (fewer, thicker cells) so they stay legible.
