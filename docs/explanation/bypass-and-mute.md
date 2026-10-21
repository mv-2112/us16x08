# Mute, bypass and what the unit does

- **Mute** silences one channel (or the master) inside the unit's mixer.
- **Mixer True Bypass** (added in firmware panel v2.10) makes the unit connect inputs to outputs matched, skipping the mixer; EQ, compression and phase therefore have no effect, which is why the panel disables them.
- **Computer Out → Stereo Bus** decides whether computer playback also goes into the master mix. On is normal.
- **LCF** is not a separate filter in the protocol: TASCAM's panel simply pins the LOW band at −12 dB. HCF in this app does the same to the HIGH shelf.
- **Solo and Link** exist on the hardware but their commands have not been captured, so they are shown disabled.
