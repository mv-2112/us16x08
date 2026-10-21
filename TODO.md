# TODO / future questions

## MIDI
Scope note: show what the *device* offers; do not add audio/MIDI configuration that belongs to macOS (Audio MIDI Setup owns sample-rate / device format / MIDI routing).
The original panel exposes nothing about the unit's MIDI ports (no strings, no UI). Questions to explore:
- Show the unit's MIDI in/out as Core MIDI endpoints on the Interface page (name, connected, activity light).
- A MIDI monitor / loopback test in the CLI and a Diagnostics page.
- Whether the mixer can be driven by MIDI (the Linux driver and the original panel say nothing, so this needs USB captures).

## Other models: profiles
Goal: make the US-16x08 a "device profile" so a US-4x4, US-2x2, US-1x2 etc. can be added without touching the UI shell.
- Profile = USB ID(s), channel counts, groups (mic/line/inst), routing sources and outputs, which DSP exists (EQ/comp), meter layout, message builders, scene mapping.
- What we could extract about the model number: the original binary is hard-wired to the US-16x08 (strings "US-16x08", scene files `US-16x08_sm1…10`, product URLs). It contains no table of other models or product IDs. Our own detection uses USB 0644:8047 (from the Linux driver) and the product string from the unit's version query (tag 0x34). So a model number *can* be read at run time (USB ID plus tag 0x34), but the original gives no list of siblings to copy from.
- The other TASCAM interfaces use different protocols; each needs its own reference (Linux driver, captures, original panels).

## Scenes
- Verify the official-format importer against a real file from `~/.config/TASCAM/` (see docs).

## Info pane
- Sample rate and bit depth are read from Core Audio (read-only, shown in the status popover with the rates macOS offers). The unit supports 44.1 / 48 / 88.2 / 96 kHz at 16 or 24 bit (retailer specs; confirm against the Reference Manual). Changing them is macOS's job (Audio MIDI Setup).
