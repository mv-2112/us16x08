# The unit cannot be read back

The US-16x08's control protocol is write-only for mixer settings: you can tell the unit "fader 3 = −10 dB" but not ask what fader 3 is now.
So the app keeps its own copy of the state, saves it as you edit, and treats it as the truth.

Consequences:
- **Connect, reconnect and scene recall always push the whole state.** A power-cycled unit forgets its settings; the next connect restores it, so the panel and the unit never disagree. There is deliberately no manual "Send all" or "Meters on/off".
- Changes made on the unit's own knobs (input gain, line/inst switch) are invisible to the panel and are not part of the state.
- If you also change settings with TASCAM's panel, the two will not know about each other, which is another reason to run only one.
- Edits are sent as you make them but coalesced (about 12 ms per control) so dragging a fader does not flood USB.
- The first launch has no saved state, so it sends defaults. If your unit currently has settings you want to keep, set them in the app first.
