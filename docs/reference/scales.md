# EQ and compressor scales

| Parameter | Range | Step | Default |
|---|---|---|---|
| EQ gain | −12…+12 dB | 1 dB | 0 |
| LOW frequency | 32 Hz … 1.6 kHz | table (32 steps) | 80 Hz |
| LOW MID / HIGH MID | 32 Hz … 18 kHz | table (64 steps) | 300 Hz / 1.2 kHz |
| HIGH frequency | 1.7 … 18 kHz | table (32 steps) | 5.0 kHz |
| Q (mids) | 0.25, 0.5, 1, 2, 4, 8, 16 | 7 values | 1.00 |
| Threshold | −32…0 dB | 1 dB | 0 |
| Ratio | 1.0, 1.1, 1.3, 1.5, 1.7, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 16.0, ∞ : 1 | 15 values | 1.0:1 |
| Gain (make-up) | 0…20 dB | 1 dB | 0 |
| Attack | 2…200 ms | 2 ms | 2 ms |
| Release | 10…1000 ms | 10 ms | 10 ms |

Graph axes: EQ 20 Hz–20 kHz logarithmic, ±15 dB drawn (gridlines ±6, ±12); compressor −48…0 dB input and output, 12 dB gridlines.
Source: TASCAM Reference Manual and the original panel's tables. The EQ curve is an RBJ filter model at 44.1 kHz, not a copy of the unit's DSP.
