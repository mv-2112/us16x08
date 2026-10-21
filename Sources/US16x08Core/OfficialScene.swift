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

/// Minimal reader/writer for the Qt "INI" files TASCAM's panel uses (QSettings, IniFormat):
/// `[Group]` headers and `key=value` lines, in insertion order.
public struct INIDocument: Equatable {
    public private(set) var order: [String] = []
    public private(set) var groups: [String: [String: String]] = [:]
    public private(set) var keyOrder: [String: [String]] = [:]

    public init() {}

    public init(text: String) {
        var current = "General"
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast())
                touch(current)
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            set(current, key, value)
        }
    }

    private mutating func touch(_ group: String) {
        if groups[group] == nil {
            groups[group] = [:]
            keyOrder[group] = []
            order.append(group)
        }
    }

    public mutating func set(_ group: String, _ key: String, _ value: String) {
        touch(group)
        if groups[group]![key] == nil { keyOrder[group]!.append(key) }
        groups[group]![key] = value
    }

    public mutating func set(_ group: String, _ key: String, _ value: Bool) { set(group, key, value ? "true" : "false") }
    public mutating func set(_ group: String, _ key: String, _ value: Int) { set(group, key, String(value)) }

    public subscript(group group: String, key key: String) -> String? { groups[group]?[key] }
    public func hasGroup(_ g: String) -> Bool { groups[g] != nil }

    public func bool(_ g: String, _ k: String) -> Bool? {
        guard let v = self[group: g, key: k]?.lowercased() else { return nil }
        if ["true", "1", "yes", "on"].contains(v) { return true }
        if ["false", "0", "no", "off"].contains(v) { return false }
        return nil
    }

    /// Integer, tolerant of text such as "-20 dB" and of "-inf" / "infinity" (returned as `infinity`).
    public func int(_ g: String, _ k: String, infinity: Int? = nil) -> Int? {
        guard let v = self[group: g, key: k] else { return nil }
        let l = v.lowercased()
        if l.contains("inf") || l == "none" { return infinity }
        return ValueParsing.integer(v)
    }

    public func text() -> String {
        var out = ""
        for g in order {
            out += "[\(g)]\n"
            for k in keyOrder[g] ?? [] { out += "\(k)=\(groups[g]?[k] ?? "")\n" }
            out += "\n"
        }
        return out
    }
}

/// TASCAM's own scene format: each scene memory of the official panel is a copy of its settings file, one Qt INI file
/// per scene (`US-16x08_sm1` … `sm10`), with the scene names in a separate `US-16x08_SceneMemory` file.
///
/// Layout read from the original panel's code (v2.10): groups `Track1`…`Track16` (keys `Phase`, `Eq`, `Comp`, `Solo`,
/// `Mute`, `Link`, `Fader_pos`/`Fader_value`, `Pan_pos`/`Pan_value`, `Eq{Low,LowMid,HighMid,High}{Gain,Freq}{Pos,Value,Text}`,
/// `Eq{LowMid,HighMid}QFreq{Pos,Text}`, `EqLowCutFilter`, `Comp{Threshold,Ratio,Gain,Attack,Release}{Pos,Text}`),
/// `LineOut1`…`LineOut8` (`LineOutSettings`), `Master`, and `Misc` (`MixerTrueBypass`, `ComputerOutToStereoBus`).
///
/// Anything this app adds beyond that (for example the high-cut filter) is an **extension**: it is written under a key
/// starting with `X_`, which the official panel does not read. Extensions are not designed to be backwards compatible.
///
/// Reading prefers the human-unit fields (`…Value`, `…Text`) over the `…Pos` slider positions, because their meaning is
/// unambiguous. Not yet verified against a real file from a real panel; see docs/reference/scene-files.md.
public enum OfficialScene {
    public struct Report: Equatable {
        public var applied = 0
        public var notes: [String] = []
        public var summary: String {
            "Applied \(applied) values." + (notes.isEmpty ? "" : " " + notes.prefix(6).joined(separator: " "))
        }
    }

    public static let namesFileName = "US-16x08_SceneMemory.ini"
    public static func fileName(slot: Int) -> String { "US-16x08_sm\(slot + 1).ini" }
    public static let bandPrefix = ["EqLow", "EqLowMid", "EqHighMid", "EqHigh"]

    // MARK: Reading

    public static func state(from doc: INIDocument, base: MixerState = MixerState()) -> (state: MixerState, report: Report) {
        var s = base
        var r = Report()
        func ok() { r.applied += 1 }

        for ch in 0..<US16x08.channelCount {
            let g = "Track\(ch + 1)"
            guard doc.hasGroup(g) else { r.notes.append("\(g) missing."); continue }
            if let v = doc.bool(g, "Phase") { s.channels[ch].phase = v; ok() }
            if let v = doc.bool(g, "Eq") { s.channels[ch].eqEnabled = v; ok() }
            if let v = doc.bool(g, "Comp") { s.channels[ch].comp.enabled = v; ok() }
            if let v = doc.bool(g, "Mute") { s.channels[ch].mute = v; ok() }
            if let v = doc.int(g, "Fader_value", infinity: -127) { s.channels[ch].faderDB = clamp(v, -127...6); ok() }
            if let v = doc.int(g, "Pan_value") ?? doc.int(g, "Pan_pos") { s.channels[ch].pan = clamp(v, -127...127); ok() }

            for band in 0..<4 {
                let p = bandPrefix[band]
                if let v = doc.int(g, "\(p)GainValue") { s.channels[ch].eq[band].gain = clamp(v + 12, 0...24); ok() }
                else if let v = doc.int(g, "\(p)GainPos") { s.channels[ch].eq[band].gain = clamp(v, 0...24); ok() }
                let range = EQBandSettings.frequencyRange(band: band)
                if let t = doc[group: g, key: "\(p)FreqText"], let hz = ValueParsing.frequencyHz(t) {
                    s.channels[ch].eq[band].frequency = clamp(EQTables.step(band: band, nearestTo: hz), range); ok()
                } else if let v = doc.int(g, "\(p)FreqPos") {
                    s.channels[ch].eq[band].frequency = clamp(v, range); ok()
                }
                if band == 1 || band == 2 {
                    let q = "\(p)QFreq"
                    if let t = doc[group: g, key: "\(q)Text"], let i = ValueParsing.qIndex(t) { s.channels[ch].eq[band].width = i; ok() }
                    else if let v = doc.int(g, "\(q)Pos") { s.channels[ch].eq[band].width = clamp(v, 0...6); ok() }
                }
            }
            if let on = doc.bool(g, "EqLowCutFilter") {
                s.channels[ch].lowCutRestoreGain = on ? 12 : nil
                if on { s.channels[ch].eq[0].gain = 0 }
                ok()
            }
            if let on = doc.bool(g, "X_EqHighCutFilter") {     // extension
                s.channels[ch].highCutRestoreGain = on ? 12 : nil
                if on { s.channels[ch].eq[3].gain = 0 }
                ok()
            }

            if let v = doc.int(g, "CompThresholdText") { s.channels[ch].comp.thresholdDB = clamp(v, CompressorSettings.thresholdRange); ok() }
            if let t = doc[group: g, key: "CompRatioText"], let i = ValueParsing.ratioIndex(t) { s.channels[ch].comp.ratioIndex = i; ok() }
            else if let v = doc.int(g, "CompRatioPos") { s.channels[ch].comp.ratioIndex = clamp(v, 0...(Messages.ratioTable.count - 1)); ok() }
            if let v = doc.int(g, "CompGainText") { s.channels[ch].comp.gainDB = clamp(v, CompressorSettings.gainRange); ok() }
            if let v = doc.int(g, "CompAttackText") {
                s.channels[ch].comp.attackMS = 2 * clamp((v - 2 + 1) / 2, 0...99) + 2; ok()
            }
            if let v = doc.int(g, "CompReleaseText") { s.channels[ch].comp.releaseSteps = clamp((v + 5) / 10, 1...100); ok() }
        }

        if doc.hasGroup("Master") {
            if let v = doc.int("Master", "Fader_value", infinity: -127) { s.masterFaderDB = clamp(v, -127...6); ok() }
            if let v = doc.bool("Master", "Mute") { s.masterMute = v; ok() }
        } else { r.notes.append("Master missing.") }

        for out in 0..<US16x08.outputCount {
            if let v = doc.int("LineOut\(out + 1)", "LineOutSettings") {
                s.routes[out] = clamp(v, 0...(Messages.routeSourceNames.count - 1)); ok()
            }
        }
        if let v = doc.bool("Misc", "MixerTrueBypass") { s.bypass = v; ok() }
        if let v = doc.bool("Misc", "ComputerOutToStereoBus") { s.bussOut = v; ok() }
        if r.applied == 0 { r.notes.append("Nothing recognised; is this a US-16x08 scene file?") }
        return (s, r)
    }

    /// `[SceneMemoryN] SceneMemory=name` (a second form with key `Name` is also accepted).
    public static func names(from doc: INIDocument) -> [Int: String] {
        var out: [Int: String] = [:]
        for n in 1...SceneStore.slotCount {
            let g = "SceneMemory\(n)"
            if let v = doc[group: g, key: "SceneMemory"] ?? doc[group: g, key: "Name"], !v.isEmpty { out[n - 1] = v }
        }
        return out
    }

    // MARK: Writing

    public static func document(from s: MixerState) -> INIDocument {
        var d = INIDocument()
        for ch in 0..<US16x08.channelCount {
            let c = s.channels[ch]
            let g = "Track\(ch + 1)"
            d.set(g, "Select", false)
            d.set(g, "Phase", c.phase)
            d.set(g, "Eq", c.eqEnabled)
            d.set(g, "Comp", c.comp.enabled)
            d.set(g, "Solo", false)
            d.set(g, "Mute", c.mute)
            d.set(g, "Link", false)
            d.set(g, "Fader_pos", c.faderDB)
            d.set(g, "Fader_value", c.faderDB)
            d.set(g, "Pan_pos", c.pan)
            d.set(g, "Pan_value", c.pan)
            for band in 0..<4 {
                let p = bandPrefix[band]
                let b = c.eq[band]
                d.set(g, "\(p)GainPos", b.gain)
                d.set(g, "\(p)GainValue", b.gain - 12)
                d.set(g, "\(p)FreqPos", b.frequency)
                let hz = EQTables.hz(band: band, step: b.frequency)
                d.set(g, "\(p)FreqText", hz < 1000 ? String(format: "%.0fHz", hz) : String(format: "%.1fkHz", hz / 1000))
                if band == 1 || band == 2 {
                    d.set(g, "\(p)QFreqPos", b.width)
                    d.set(g, "\(p)QFreqText", EQTables.qLabel(b.width))
                }
            }
            d.set(g, "EqLowCutFilter", c.lowCutRestoreGain != nil)
            d.set(g, "X_EqHighCutFilter", c.highCutRestoreGain != nil)          // extension
            d.set(g, "CompThresholdPos", c.comp.thresholdDB)
            d.set(g, "CompThresholdText", "\(c.comp.thresholdDB)dB")
            d.set(g, "CompRatioPos", c.comp.ratioIndex)
            d.set(g, "CompRatioText", CompressorSettings.ratioLabel(c.comp.ratioIndex))
            d.set(g, "CompGainPos", c.comp.gainDB)
            d.set(g, "CompGainText", "\(c.comp.gainDB)dB")
            d.set(g, "CompAttackPos", (c.comp.attackMS - 2) / 2)
            d.set(g, "CompAttackText", "\(c.comp.attackMS)ms")
            d.set(g, "CompReleasePos", c.comp.releaseSteps)
            d.set(g, "CompReleaseText", "\(c.comp.releaseMS)ms")
        }
        d.set("Master", "Fader_pos", s.masterFaderDB)
        d.set("Master", "Fader_value", s.masterFaderDB)
        d.set("Master", "Mute", s.masterMute)
        for out in 0..<US16x08.outputCount { d.set("LineOut\(out + 1)", "LineOutSettings", s.routes[out]) }
        d.set("Misc", "MixerTrueBypass", s.bypass)
        d.set("Misc", "ComputerOutToStereoBus", s.bussOut)
        return d
    }

    public static func namesDocument(_ names: [String]) -> INIDocument {
        var d = INIDocument()
        for (i, n) in names.enumerated() { d.set("SceneMemory\(i + 1)", "SceneMemory", n) }
        return d
    }

    private static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
}
