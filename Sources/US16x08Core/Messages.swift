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

public enum US16x08 {
    public static let vendorID: UInt16 = 0x0644      // TEAC / TASCAM
    public static let productID: UInt16 = 0x8047     // US-16x08
    public static let channelCount = 16
    public static let outputCount = 8

    /// USB vendor requests on endpoint 0.
    public enum Request {
        public static let set: UInt8 = 0x1D          // host -> device, bmRequestType 0x40
        public static let setType: UInt8 = 0x40
        public static let meters: UInt8 = 0x1E       // device -> host, bmRequestType 0xC0
        public static let metersType: UInt8 = 0xC0
        public static let meterFrameLength = 64
    }
}

/// Byte-exact message builders.
///
/// The wire format comes from the Linux kernel driver `sound/usb/mixer_us16x08.c`
/// (GPL-2.0-or-later, (c) 2016 Detlef Urban), which was derived from the
/// original TASCAM panel's USB traffic. Every builder here is checked against
/// golden vectors in the unit tests.
public enum Messages {

    // MARK: Templates (identical to the driver's)
    private static let mixIn: [UInt8]  = [0x61, 0x02, 0x04, 0x62, 0x02, 0x01, 0x81, 0x02, 0x00, 0x00, 0x00]
    private static let mixOut: [UInt8] = [0x61, 0x02, 0x02, 0x62, 0x02, 0x01, 0x81, 0x02, 0x00, 0x00, 0x00]
    private static let routeTemplate: [UInt8] = [
        0x61, 0x02, 0x03, 0x62, 0x02, 0x01, 0x41, 0x01, 0x61, 0x02,
        0x01, 0x62, 0x02, 0x01, 0x42, 0x01, 0x43, 0x01, 0x00, 0x00,
    ]
    private static let compTemplate: [UInt8] = [
        0x61, 0x02, 0x04, 0x62, 0x02, 0x01,
        0x91, 0x02, 0xf0, 0x92, 0x02, 0x0a, 0x93, 0x02, 0x02,
        0x94, 0x02, 0x01, 0x95, 0x02, 0x03, 0x96, 0x02, 0x01,
        0x97, 0x02, 0x01, 0x00, 0x00,
    ]
    private static let eqTemplate: [UInt8] = [
        0x61, 0x02, 0x04, 0x62, 0x02, 0x01,
        0x51, 0x02, 0x04, 0x52, 0x02, 0x0c, 0x53, 0x02, 0x0f,
        0x54, 0x02, 0x02, 0x55, 0x02, 0x01, 0x00, 0x00,
    ]

    /// Compressor ratio steps as sent on the wire (ratio x 10; 0xFF = infinity?).
    public static let ratioTable: [UInt8] = [
        0x0a, 0x0b, 0x0d, 0x0f, 0x11, 0x14, 0x19, 0x1e,
        0x23, 0x28, 0x32, 0x3c, 0x50, 0xa0, 0xff,
    ]

    /// UNVERIFIED: the Linux driver sends the high-band EQ frequency without
    /// the +0x20 the hardware seems to expect (its own default of 0x0f vs the
    /// device template's range comment of 32-47). We add 0x20 here. Set to 0 to
    /// reproduce the Linux driver's behaviour exactly. The self-test checks this.
    public static var highBandFrequencyOffset = 0x20

    // MARK: Helpers
    private static func wire(_ v: Int, _ r: ClosedRange<Int>) -> UInt8 {
        UInt8(bitPattern: Int8(clamping: min(max(v, r.lowerBound), r.upperBound)))
    }
    private static func byte(_ v: Int, _ r: ClosedRange<Int>) -> UInt8 {
        UInt8(clamping: min(max(v, r.lowerBound), r.upperBound))
    }
    private static func channelMessage(_ ch: Int, control: UInt8, value: UInt8) -> [UInt8] {
        var m = mixIn
        m[5] = UInt8(clamping: ch + 1)
        m[6] = control
        m[8] = value
        return m
    }
    private static func masterMessage(control: UInt8, value: UInt8) -> [UInt8] {
        var m = mixOut
        m[5] = 1
        m[6] = control
        m[8] = value
        return m
    }

    // MARK: Input channels (0-based channel index)
    /// Fader in dB, -127...+6. -127 is "-inf".
    public static func fader(channel: Int, db: Int) -> [UInt8] {
        channelMessage(channel, control: 0x81, value: wire(db, -127...6))
    }
    /// Pan, -127 (left) ... +127 (right), 0 = centre.
    public static func pan(channel: Int, position: Int) -> [UInt8] {
        channelMessage(channel, control: 0x82, value: wire(position, -127...127))
    }
    public static func mute(channel: Int, on: Bool) -> [UInt8] {
        channelMessage(channel, control: 0x83, value: on ? 1 : 0)
    }
    public static func phase(channel: Int, on: Bool) -> [UInt8] {
        channelMessage(channel, control: 0x85, value: on ? 1 : 0)
    }

    // MARK: Master / bus
    public static func masterFader(db: Int) -> [UInt8] {
        masterMessage(control: 0x81, value: wire(db, -127...6))
    }
    public static func masterMute(on: Bool) -> [UInt8] {
        masterMessage(control: 0x83, value: on ? 1 : 0)
    }
    /// Mixer True Bypass. (The original panel's `set_truebypass` sends this same 0x45 message.)
    public static func bypass(on: Bool) -> [UInt8] { [0x45, 0x02, on ? 1 : 0, 0x00, 0x00] }
    /// Computer Out to Stereo Bus ON/OFF. (The original panel's `set_send_stereobus` sends this same 0x44 message.)
    public static func bussOut(on: Bool) -> [UInt8] { [0x44, 0x02, on ? 1 : 0, 0x00, 0x00] }

    // MARK: Routing
    /// Names for route source indices 0...9.
    public static let routeSourceNames = [
        "Master Left", "Master Right",
        "Computer 1", "Computer 2", "Computer 3", "Computer 4",
        "Computer 5", "Computer 6", "Computer 7", "Computer 8",
    ]
    /// `output` 0...7 (line outs 1-8), `sourceIndex` 0...9 (see `routeSourceNames`).
    public static func route(output: Int, sourceIndex: Int) -> [UInt8] {
        var m = routeTemplate
        let idx = min(max(sourceIndex, 0), 9)
        if idx < 2 {
            m[2] = 0x02
            m[5] = UInt8((idx & 0x0f) + 1)
        } else {
            m[2] = 0x03
            m[5] = UInt8(((idx - 2) & 0x0f) + 1)
        }
        m[13] = UInt8(min(max(output, 0), 7) + 1)
        return m
    }

    // MARK: DSP
    public static func compressor(channel: Int, _ c: CompressorSettings) -> [UInt8] {
        var m = compTemplate
        m[5] = UInt8(clamping: channel + 1)
        m[8] = wire(c.thresholdDB, CompressorSettings.thresholdRange)
        m[11] = ratioTable[min(max(c.ratioIndex, 0), ratioTable.count - 1)]
        m[14] = byte(c.attackMS, CompressorSettings.attackRange)
        m[17] = byte(c.releaseSteps, 1...100)
        m[20] = byte(c.gainDB, CompressorSettings.gainRange)
        m[26] = c.enabled ? 1 : 0
        return m
    }

    /// `band`: 0 low, 1 low-mid, 2 high-mid, 3 high. The device wants all four
    /// parameters of a band in every message, plus the global EQ switch.
    public static func eqBand(channel: Int, band: Int, _ s: EQBandSettings, enabled: Bool) -> [UInt8] {
        let b = min(max(band, 0), 3)
        var m = eqTemplate
        m[5] = UInt8(clamping: channel + 1)
        m[8] = UInt8(b + 1)
        m[11] = byte(s.gain, 0...24)
        m[14] = byte(s.frequency + (b == 3 ? highBandFrequencyOffset : 0), 0...255)
        m[17] = (b == 1 || b == 2) ? byte(s.width, 0...6) : 0xFF
        m[20] = enabled ? 1 : 0
        return m
    }

    // MARK: Identity
    /// Asks the unit to report its version and build (reply tags 0x32 / 0x33, 16-bit LE each).
    /// Taken from the original panel's `usctl_get_version_common`.
    public static let versionQuery: [UInt8] = [0x31, 0x01, 0x00, 0x00]

    // MARK: Metering
    public static let meterInit1: [UInt8] = [0x71, 0x01, 0x00, 0x00]
    /// `compChannel` is 1-based: which channel's compressor reduction to fetch.
    public static func meterInit2(compChannel: Int) -> [UInt8] {
        [0x62, 0x02, UInt8(clamping: compChannel), 0x61, 0x02, 0x04, 0xb1, 0x01, 0x00, 0x00]
    }
}

// MARK: - Meter frames

public struct MeterLevels: Equatable {
    public var input = [Int](repeating: 0, count: US16x08.channelCount)
    public var master = [Int](repeating: 0, count: 2)
    public var compReduction = [Int](repeating: 0, count: US16x08.channelCount)
    public static let maxValue = 0x7FFF
    public init() {}
}

/// Meter calibration, confirmed on a real unit (autotest, Oct 2026):
/// - Level meters are linear amplitude with 0x7FFF = digital full scale
///   (a -24 dBFS tone reads -23.7 dBFS; fader steps of -20/-30 dB read -19.8/-30.2 dB).
/// - The compressor meter is the applied linear gain x 0x7FFF, so reduction in dB = -20*log10(raw/0x7FFF)
///   (raw 1740 -> 25.5 dB while the output really dropped 25.3 dB). 0 means "not reporting".
public enum MeterScale {
    public static func dBFS(_ raw: Int) -> Double? {
        raw > 0 ? 20.0 * log10(Double(raw) / Double(MeterLevels.maxValue)) : nil
    }
    public static func reductionDB(_ raw: Int) -> Double {
        guard raw > 0 else { return 0 }
        return max(0, -20.0 * log10(Double(raw) / Double(MeterLevels.maxValue)))
    }
}

public enum MeterParser {
    /// A frame is up to six 10-byte records starting at byte 4.
    public static func update(_ levels: inout MeterLevels, frame: [UInt8]) {
        for set in 0..<6 {
            let base = set * 10 + 4
            guard base + 9 < frame.count else { break }
            let a0 = frame[base], a1 = frame[base + 1], a2 = frame[base + 2]
            let b0 = frame[base + 3], b2 = frame[base + 5]
            let c0 = frame[base + 6]
            let value = Int(frame[base + 8]) + (Int(frame[base + 9]) << 8)
            let ch = Int(b2) - 1
            if ch < 0 || a0 != 0x61 || a1 != 0x02 || b0 != 0x62 { continue }
            if a2 == 0x04 && ch < US16x08.channelCount {
                if c0 == 0x72 { levels.input[ch] = value }
                if c0 == 0xb2 { levels.compReduction[ch] = value }
            } else if a2 == 0x02 && ch < 2 {
                levels.master[ch] = value
            }
        }
    }
}

public func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
