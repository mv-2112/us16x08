# Shape a channel with EQ

1. Click the channel strip. The docked panel shows that channel.
2. Switch **On** (or press the strip's **EQ** chip).
3. Adjust a band by any of:
   - dragging its node on the graph (left/right = frequency, up/down = gain);
   - turning its **GAIN**, **FREQ** or **Q** knob (drag up/down; double-click resets);
   - typing in the black number box and pressing Return. `1.2k`, `1200`, `1.2 kHz` and `1.2` all mean 1.2 kHz. The value snaps to the nearest step the unit supports.
4. Q exists only on the two mid bands.

**Low-cut (LCF):** press **LCF** on the LOW row. As in TASCAM's panel this pins the LOW band at −12 dB; pressing it again restores the previous gain. The LOW gain knob is locked while it is on.
**High-cut (HCF):** same idea on the HIGH row. This is an addition; TASCAM's panel has no HCF.

**Copy an EQ/compressor to another channel:** the **Channel** menu on the EQ card → *Copy DSP*, select another strip, → *Paste DSP*. *Reset DSP* returns a channel to defaults.

The graph is logarithmic in frequency (20 Hz – 20 kHz) and shows ±12 dB gain steps; see [Scales](../reference/scales.md).
