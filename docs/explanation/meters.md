# Meters, peaks and calibration

The unit reports levels as 16-bit numbers. On real hardware, with the automated test playing known tones, these turned out to be **linear amplitude with 0x7FFF = digital full scale**: a −24 dBFS tone read −23.7 dBFS and fader steps read within 0.3 dB.
The compressor meter is different: it reports the **gain being applied** (× 0x7FFF), so reduction in dB is −20·log10(raw/32767).
Centre pan lowers each side by 3 dB (a −3 dB pan law).

The app polls the unit about 50 times a second in four protocol steps, so every meter refreshes about 12 times a second, and redraws from a lock-protected store at 30 fps on its own timer. Meter data is deliberately **not** published through the main observable model: doing so re-rendered the whole window at USB speed, used 100% CPU and made menus flicker (see KNOWN_ISSUES BUG-002).

Open question: with all inputs open the master meters idle near −52 dBFS. This may be a hot open input rather than a fault; see BUG-001.
