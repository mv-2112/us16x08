# Connect, and recover when it does not

**Normal case:** nothing to do. The app connects at launch and whenever the unit is plugged in.

**Check state:** click the title-bar status chip. Pages: Device, Audio, Firmware, Status. Hover it for a one-line summary.

**Unit shows red / not connected**
1. Check the cable and that the unit is powered.
2. Click the chip → **Reconnect**.
3. Open **Window → Diagnostics Log** (⌥⌘L) and look for the last error.

**"Unit not responding, retrying…" or error `0xe00002ed`**
- Quit TASCAM's own panel (the chip shows an orange triangle when it is running).
- Try a different USB port, preferably without a hub.
- Unplug and re-plug the unit; the app reconnects and resends your settings.
- If it keeps happening, use **Copy All** in the Diagnostics window and add it to your bug report ([KNOWN_ISSUES.md](../../KNOWN_ISSUES.md), BUG-003).

**Work without the unit:** the mixer, EQ, compressor, routing and scenes stay editable offline. Switches that live in the unit
(Mixer True Bypass, Computer Out → Stereo Bus) are disabled until it is connected. Everything is sent when it connects.
