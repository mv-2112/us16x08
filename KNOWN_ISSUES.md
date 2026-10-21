# Known issues and open items

## BUG-001 (potential, unconfirmed): unexplained signal on the original panel's meters
**Seen:** Oct 2026, while running the unofficial panel/tools next to TASCAM's original Settings Panel.
The original panel showed signal on Analog 13, 14, 15 and 16 (13 and 16 strongest, 15 lowest) and on Master L/R.
Analog 1-12 were silent. The user heard noise from the unit.

**Why it may not be ours**
- The only code here that makes sound is `us16x08ctl autotest`. Stage 1 puts a 1 kHz tone on the master L/R only
  (via Computer out to Stereo BUS). Stage 2 puts a tone on input 16 only (LINE OUT 8 -> LINE IN 16 cable).
  Neither can put signal on inputs 13, 14 or 15. The GUI app and the other CLI commands play no audio.
- Inputs 11-16 are the rear line inputs. A cable plugged in at one end, or hum on a high-gain input, can show on those meters.
- Anything playing from the Mac goes to the master while "Computer out to Stereo BUS" is on.

**Why it may be ours**
- If `autotest` is interrupted (Ctrl-C or a crash) its end-of-run cleanup does not run, so the unit can be left in a
  non-default state (hard pan, master mute, bus-out off, EQ/comp on channel 16). That would not create noise, but could
  explain odd levels afterwards.

**Status:** machine rebooted; waiting to see if it recurs. No change made.

**If it comes back, capture:**
1. `pgrep -fl "us16x08ctl|US16x08Panel|autotest"` (is anything of ours running?).
2. A screenshot of the original panel (which meters move).
3. `swift run us16x08ctl meters 10` with nothing playing: raw and dBFS peaks per input.
4. What is plugged into the rear line inputs 11-16, and which app is playing to the Mac's audio output.
5. Whether the noise stops when the original panel is closed, then when our app is closed.

## Backlog / unverified (collected so far)
- Master meters idle around -52 dBFS (raw ~82) with the Mac silent; input meters idle near raw 1. Hypothesis: a hot, open
  input (guitar at full gain on input 10) feeds the master. The autotest now prints which inputs are above idle.
- `autotest` should restore the baseline on Ctrl-C (install a SIGINT handler).
- Mid-band 16 kHz and 17 kHz table entries (steps 61, 62) are inferred, not read from the original's mid function.
- Not implemented (protocol not captured yet): Solo, Link, LCF, channel names, device-side scene memory.
- The compressor graph has no live input/output level bars (only the gain-reduction meter is available).
- Whether the input meters are pre- or post-fader: the autotest records this as an INFO line.
- The original's "Mode" field (AUDIO INTERFACE) is not read yet.

## BUG-002 (fix in this build, needs confirmation): 100% CPU and flickering menus
**Seen:** Oct 2026. The app ran at about 100% CPU and menus flickered.

**Cause (suspected; the process sample has not been analysed yet):** every meter tick (40 per second) and every logged USB
message was published through the single `AppModel`, which every view observes. SwiftUI therefore rebuilt the whole window
(toolbar menus, pickers, DSP panel, 16 strips) at USB polling speed. Rebuilt menus are what flickered.

**Fix:** meters now live in a plain `MeterStore` that each meter view reads on its own 30 fps timeline, with no main-thread hop
and no published state. The log lives in a `LogStore` observed only by the Diagnostics window and refreshed at 4 Hz. The poller
runs at 50 Hz with timer leeway. Controls still send immediately when changed (no polling for control changes).

**Evidence (process sample, build 0.1.0 (1)):** the main thread was busy for about 88% of the sample (684 of 775 samples),
almost all of it in SwiftUI's update flush (AttributeGraph), with our USB code only 4-8 samples. The stack still showed the
old `AppModel.setMeters` closure dispatching to the main queue, i.e. the pre-fix design. This matches the cause above.

**To confirm:** run the new build, check Activity Monitor, and if it is still high take a sample while it is busy:
`sample US16x08Panel 5 -file ~/Desktop/us16x08-sample.txt` (or Activity Monitor > select the process > Sample Process) and attach it.

## BUG-003 (mitigated, needs confirmation): "meter poll: USB send failed ... 0xe00002ed"
**What it is:** `0xe00002ed` is `kIOReturnNotResponding`: the unit stopped answering a control request. The error text now says so.

**Likely causes:** TASCAM's own panel running at the same time (both poll the same unit and share its reply stream, as seen when both
were open), the unit busy or re-enumerating, the unit's auto power-save, or a flaky USB hub or cable.

**Mitigations in this build:** transfers retry up to five times 5 ms apart for transient errors (as the original does); the meter
poller drops to once a second after about 0.4 s of failures and resumes by itself instead of stopping; a warning shows in the
status panel whenever TASCAM's panel is running.

**To confirm:** does it still happen with only our app running, directly on a port (no hub)? Attach the Diagnostics log.

## Notes from the Golden Gate redesign
- All SwiftUI code in the redesign is uncompiled; expect a round of compile fixes after the first `swift build`.
- First launch has no saved state and sends defaults to the unit on connect (the unit cannot be read back). Backlog: ask once before overwriting.
- Meter pre/post-fader behaviour still unconfirmed. SOLO/LINK are shown disabled (protocol not captured).
- Window size derives from `Layout.swift`; verify on a real display that fader height is comfortable at the minimum height.

## Scene format (official TASCAM files)
- Groups and keys were taken from the original panel's code (`Track1…16`, `Master`, `LineOut1…8`, `Misc`; keys `Fader_value`, `Pan_value`, `Eq*GainValue`, `Eq*FreqText`, `Comp*Text`, `EqLowCutFilter`…). Not yet checked against a real file: what `…Pos` holds (slider position vs. value), how `-inf` and pan are written, whether the INI has extra header groups. Importer prefers value/text keys and ignores unknowns.
- Where the official panel stores the files is inferred from Qt's rules (`~/.config/TASCAM/US-16x08_*.ini`); confirm on your Mac.
- Exporting writes `Fader_pos`/`Pan_pos` as plain values, which may not match the official slider positions.
