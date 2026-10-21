# Window and controls

## Title bar / toolbar
| Item | Meaning |
|---|---|
| ● US-16x08 | Status: green connected, red not. Click for the pager (Device, Audio, Firmware, Status); ⚠ = a warning (meters retrying or the original panel is running). Hover for a summary. |
| Mixer · Routing · Interface · Scenes | Sections |
| True Bypass | Mixer True Bypass; disabled when disconnected |
| Scene | Quick recall |
| Appearance | Auto / Light / Dark |

Closing the main window quits the app. The toolbar follows Safari's recipe: tabs left, flexible space, centred status chip, flexible space, Scene / Appearance / True Bypass right. Requires macOS 26 or later (built for Golden Gate).

## Mixer
**Docked DSP panel** (selected channel). EQ: graph plus rows HIGH, HIGH MID, LOW MID, LOW, each with GAIN, FREQ and (mids) Q; LCF on LOW, HCF on HIGH. Compressor: transfer graph, timing sketch, GR bar, THRESHOLD, RATIO, GAIN, ATTACK, RELEASE.

**Controls:** knob = drag up/down, double-click resets; number box = type then Return, snaps to a legal value; fader = drag, double-click 0 dB.

**Input groups:** MIC 1–8 (XLR), LINE/INST 9–10 (front jacks), LINE 11–16 (rear). Input gain for 1–10 is on the unit.

**Strip (top to bottom):** channel number · PHASE · EQ · COMP · SOLO (not yet available) · MUTE · pan knob (tooltip shows L/R percentage) · fader with LED meter · level in dB · LINK (not yet available).

**MASTER column** uses the same rows: BYPASS on the EQ row, MUTE on the MUTE row, two LED meters, PEAKS (clears all peak holds and clip lamps) on the LINK row.

## Defaults
EQ: 80 Hz, 300 Hz, 1.2 kHz, 5.0 kHz; Q 1.00; gain 0. Compressor: threshold 0 dB, ratio 1.0:1, gain 0 dB, attack 2 ms, release 10 ms. Faders 0 dB, pan centre.

## Status pager (click the title-bar chip)
Device (name, connection, USB speed, release) · Audio (sample rate, **bit depth**, rates macOS offers; the unit supports 44.1 / 48 / 88.2 / **96 kHz** at 16 or 24 bit) · Firmware · Status (last event, scene, warnings).

## Routing
Shows the unit's physical connectors as line drawings: XLR mic inputs, ¼″ jack inputs and outputs, and the USB-B port, wired to the eight line outs.
