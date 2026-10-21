// SPDX-License-Identifier: GPL-2.0-or-later
//
// US-16x08 Panel: an unofficial control panel for the TASCAM US-16x08.
// Not affiliated with TASCAM / TEAC Corporation, the Linux kernel or ALSA
// maintainers, or the GNU Project.
//
// Derivative work. The USB protocol knowledge used here comes from the Linux
// kernel driver sound/usb/mixer_us16x08.c, Copyright (c) 2016 by Detlef Urban,
// GPL-2.0-or-later.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation; either version 2 of the License, or (at your option) any later
// version. It is distributed WITHOUT ANY WARRANTY. See the file COPYING.

import Foundation

/// Frequency and Q tables read out of the original TASCAM panel (its calLow/Mid/HighFreqExchangeValue and
/// calQExchangeValue functions) and cross-checked with the Reference Manual defaults:
/// LOW 80 Hz, LOW MID 300 Hz, HIGH MID 1.2 kHz, HIGH 5.0 kHz, Q 1.00.
///
/// The device has ONE 64-entry frequency scale. LOW uses steps 0...31 (32 Hz - 1.6 kHz), the two mid bands
/// use 0...63 (32 Hz - 18 kHz) and HIGH uses the top half, 32...63 (1.7 kHz - 18 kHz), which is why its
/// wire value carries a +0x20 offset.
///
/// 16 kHz and 17 kHz (mid steps 61 and 62) are inferred: the original's mid function does not emit them as
/// literals, but its HIGH function lists them and the scale is shared.
public enum EQTables {
    public static let freqTable: [Double] = [
        32, 40, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 225, 250, 300, 350,
        400, 450, 500, 600, 700, 800, 850, 900, 950, 1000, 1100, 1200, 1300, 1400, 1500, 1600,
        1700, 1800, 1900, 2000, 2200, 2400, 2600, 2800, 3000, 3200, 3400, 3600, 3800, 4000, 4500, 5000,
        5500, 6000, 6500, 7000, 7500, 8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000,
    ]

    /// Q for mid-band width steps 0...6.
    public static let qValues: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16]

    private static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }

    /// `band`: 0 low, 1 low-mid, 2 high-mid, 3 high. `step` is the band's own step (HIGH: 0...31).
    public static func hz(band: Int, step: Int) -> Double {
        switch band {
        case 0: return freqTable[clamp(step, 0...31)]
        case 3: return freqTable[32 + clamp(step, 0...31)]
        default: return freqTable[clamp(step, 0...63)]
        }
    }

    /// The band step whose frequency is closest (on a log scale) to `hz`.
    public static func step(band: Int, nearestTo hz: Double) -> Int {
        let range = band == 0 ? 0...31 : (band == 3 ? 32...63 : 0...63)
        var best = range.lowerBound
        var bestDistance = Double.infinity
        for i in range {
            let d = abs(log(freqTable[i] / max(hz, 1)))
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return band == 3 ? best - 32 : best
    }

    /// "80 Hz", "1.2 kHz", "18.0 kHz" (the manual's style).
    public static func label(hz: Double) -> String {
        hz < 1000 ? String(format: "%.0f Hz", hz) : String(format: "%.1f kHz", hz / 1000)
    }
    public static func label(band: Int, step: Int) -> String { label(hz: hz(band: band, step: step)) }

    public static func qLabel(_ width: Int) -> String {
        String(format: "%.2f", qValues[clamp(width, 0...(qValues.count - 1))])
    }
}

/// Magnitude response of the four-band EQ using standard (RBJ) biquads at 44.1 kHz: shelves for LOW/HIGH
/// (slope 1), bells for the mids. This is a close visual model, not a bit-exact copy of the unit's DSP.
public enum EQResponse {
    public static let sampleRate = 44100.0

    public static func magnitudeDB(bands: [EQBandSettings], atHz f: Double) -> Double {
        var total = 0.0
        for b in 0..<min(4, bands.count) {
            let gain = Double(bands[b].gain - 12)
            if gain == 0 { continue }
            let f0 = EQTables.hz(band: b, step: bands[b].frequency)
            let q = EQTables.qValues[min(max(bands[b].width, 0), EQTables.qValues.count - 1)]
            let (num, den) = coefficients(band: b, f0: f0, gainDB: gain, q: q)
            total += responseDB(num, den, atHz: f)
        }
        return total
    }

    private static func coefficients(band: Int, f0: Double, gainDB: Double, q: Double) -> ([Double], [Double]) {
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let c = cos(w0)
        if band == 1 || band == 2 {
            let alpha = sin(w0) / (2.0 * q)
            return ([1 + alpha * a, -2 * c, 1 - alpha * a], [1 + alpha / a, -2 * c, 1 - alpha / a])
        }
        let alpha = sin(w0) / 2.0 * 2.0.squareRoot()          // shelf slope S = 1
        let s = 2.0 * a.squareRoot() * alpha
        if band == 0 {
            return ([a * ((a + 1) - (a - 1) * c + s), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - s)],
                    [(a + 1) + (a - 1) * c + s, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - s])
        }
        return ([a * ((a + 1) + (a - 1) * c + s), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - s)],
                [(a + 1) - (a - 1) * c + s, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - s])
    }

    private static func power(_ c: [Double], _ w: Double) -> Double {
        let re = c[0] + c[1] * cos(w) + c[2] * cos(2 * w)
        let im = -(c[1] * sin(w) + c[2] * sin(2 * w))
        return re * re + im * im
    }

    private static func responseDB(_ num: [Double], _ den: [Double], atHz f: Double) -> Double {
        let w = 2.0 * Double.pi * f / sampleRate
        return 10.0 * log10(power(num, w) / power(den, w))
    }
}
