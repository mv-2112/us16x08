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

/// Fader position <-> dB. Position runs 0 (bottom, -inf) ... 1 (top, +6 dB) with 0 dB at 80% of the travel,
/// like a console fader, instead of a linear dB scale.
public enum FaderTaper {
    private static let table: [(db: Double, pos: Double)] = [
        (-127, 0.0), (-60, 0.04), (-40, 0.17), (-30, 0.27), (-20, 0.42), (-10, 0.62), (0, 0.80), (6, 1.0),
    ]
    /// dB values that get a tick mark on the scale.
    public static let tickDBs: [Int] = [6, 0, -10, -20, -30, -40, -60]

    public static func position(db: Int) -> Double {
        let d = Double(min(max(db, -127), 6))
        for i in 1..<table.count where d <= table[i].db {
            let a = table[i - 1], b = table[i]
            return a.pos + (b.pos - a.pos) * (d - a.db) / (b.db - a.db)
        }
        return 1
    }

    /// Below about 3% of the travel the fader reads -inf (-127 on the wire).
    public static func db(position p: Double) -> Int {
        let q = min(max(p, 0), 1)
        if q < 0.03 { return -127 }
        for i in 1..<table.count where q <= table[i].pos {
            let a = table[i - 1], b = table[i]
            return Int((a.db + (b.db - a.db) * (q - a.pos) / (b.pos - a.pos)).rounded())
        }
        return 6
    }
}

/// Turns what a person types into a number box ("+4", "1.2k", "3:1", "inf") back into a control value.
public enum ValueParsing {
    /// "+4", "-2 dB", "\u{2212}2" -> Int.
    public static func integer(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: "\u{2212}", with: "-")
        let kept = t.filter { "0123456789+-.".contains($0) }
        guard let d = Double(kept) else { return nil }
        return Int(d.rounded())
    }

    /// "300", "300 Hz", "1.2k", "5 kHz", "1.2" (below 20 means kHz) -> Hz.
    public static func frequencyHz(_ text: String) -> Double? {
        var t = text.lowercased().replacingOccurrences(of: "hz", with: "").trimmingCharacters(in: .whitespaces)
        let isK = t.hasSuffix("k")
        if isK { t.removeLast() }
        guard let v = Double(t.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return (isK || v < 20) ? v * 1000 : v
    }

    /// "3", "3.0:1", "inf", "\u{221E}" -> index into `Messages.ratioTable`.
    public static func ratioIndex(_ text: String) -> Int? {
        let t = text.lowercased()
        let last = Messages.ratioTable.count - 1
        if t.contains("inf") || t.contains("\u{221E}") || t.contains("max") { return last }
        var s = t
        if let colon = s.firstIndex(of: ":") { s = String(s[s.startIndex..<colon]) }
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        var best = 0
        var bestD = Double.infinity
        for (i, raw) in Messages.ratioTable.enumerated() where raw != 0xff {
            let d = abs(log(Double(raw) / 10.0 / v))
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// "1", "0.5", "4.00" -> index into `EQTables.qValues`.
    public static func qIndex(_ text: String) -> Int? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        var best = 0
        var bestD = Double.infinity
        for (i, q) in EQTables.qValues.enumerated() {
            let d = abs(log(q / v))
            if d < bestD { bestD = d; best = i }
        }
        return best
    }
}
