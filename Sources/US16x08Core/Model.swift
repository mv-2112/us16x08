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

public struct EQBandSettings: Codable, Equatable {
    /// 0...24, 12 = flat (so dB = gain - 12).
    public var gain: Int
    /// Raw step. Low band 0...31, mid bands 0...63, high band 0...31 (offset added on the wire).
    public var frequency: Int
    /// Mid bands only: 0...6.
    public var width: Int

    public init(gain: Int = 12, frequency: Int, width: Int = 2) {
        self.gain = gain
        self.frequency = frequency
        self.width = width
    }

    /// Power-on defaults used by the Linux driver for each band.
    public static let defaults: [EQBandSettings] = [
        EQBandSettings(frequency: 0x05),
        EQBandSettings(frequency: 0x0e),
        EQBandSettings(frequency: 0x1b),
        EQBandSettings(frequency: 0x0f),
    ]
    public static let bandNames = ["Low", "Low-Mid", "High-Mid", "High"]
    public static func frequencyRange(band: Int) -> ClosedRange<Int> { (band == 1 || band == 2) ? 0...63 : 0...31 }
}

public struct CompressorSettings: Codable, Equatable {
    // Ranges and defaults from the TASCAM Reference Manual (also what the original panel's own code does):
    // THRESHOLD -32...0 dB (0), RATIO 1.0:1...inf:1 (1.0:1), GAIN 0...20 dB (0),
    // ATTACK 2...200 ms (2; the panel moves in 2 ms steps), RELEASE 10...1000 ms (10; 10 ms steps).
    public static let thresholdRange = -32...0
    public static let gainRange = 0...20
    public static let attackRange = 2...200
    public static let releaseRange = 10...1000

    public var enabled = false
    /// -32...0 dB
    public var thresholdDB = 0
    /// Index into `Messages.ratioTable` (0...14)
    public var ratioIndex = 0
    /// 2...200 ms
    public var attackMS = 2
    /// 1...100 (x10 ms)
    public var releaseSteps = 1
    /// Make-up gain 0...20 dB
    public var gainDB = 0
    public init() {}

    /// Release in milliseconds (the wire value is in units of 10 ms).
    public var releaseMS: Int { releaseSteps * 10 }

    public static func ratioLabel(_ index: Int) -> String {
        let v = Int(Messages.ratioTable[min(max(index, 0), Messages.ratioTable.count - 1)])
        if v == 0xff { return "∞:1" }
        return String(format: "%.1f:1", Double(v) / 10.0)
    }
}

public struct ChannelState: Codable, Equatable, Identifiable {
    public var id: Int
    /// -127 ... +6 dB (-127 = off/-inf)
    public var faderDB = 0
    /// -127 ... +127
    public var pan = 0
    public var mute = false
    public var phase = false
    public var eqEnabled = false
    public var eq = EQBandSettings.defaults
    public var comp = CompressorSettings()
    /// Low-cut filter, as the original panel does it: the LOW band pinned at -12 dB. Non-nil while on; holds the
    /// gain to restore. (Optional so state saved by older builds still decodes.)
    public var lowCutRestoreGain: Int?
    /// High-cut shelf (our own convenience, not in the original): the HIGH band pinned at -12 dB.
    public var highCutRestoreGain: Int?
    public init(id: Int) { self.id = id }
}

public struct MixerState: Codable, Equatable {
    public var channels: [ChannelState] = (0..<US16x08.channelCount).map { ChannelState(id: $0) }
    public var masterFaderDB = 0
    public var masterMute = false
    /// "Mixer True Bypass" (added in v2.10): input and output matched binary, mixer processing bypassed.
    public var bypass = false
    /// "Computer Out to Stereo Bus". ON is the normal state; v2.10 only added the OFF choice.
    public var bussOut = true
    /// Source index (see `Messages.routeSourceNames`) feeding each of the 8 line outs.
    /// Power-on defaults from the Linux driver: outs 1-2 = master L/R, outs 3-8 = computer 3-8.
    public var routes = [0, 1, 4, 5, 6, 7, 8, 9]
    public init() {}

    /// Everything, in a sensible order, for "send all to device".
    public func syncMessages() -> [OutboundMessage] {
        var out: [OutboundMessage] = []
        for (o, r) in routes.enumerated() {
            out.append(OutboundMessage(key: "route\(o)", bytes: Messages.route(output: o, sourceIndex: r)))
        }
        out.append(OutboundMessage(key: "masterFader", bytes: Messages.masterFader(db: masterFaderDB)))
        out.append(OutboundMessage(key: "masterMute", bytes: Messages.masterMute(on: masterMute)))
        out.append(OutboundMessage(key: "bussOut", bytes: Messages.bussOut(on: bussOut)))
        out.append(OutboundMessage(key: "bypass", bytes: Messages.bypass(on: bypass)))
        for ch in channels {
            let i = ch.id
            out.append(OutboundMessage(key: "fader\(i)", bytes: Messages.fader(channel: i, db: ch.faderDB)))
            out.append(OutboundMessage(key: "pan\(i)", bytes: Messages.pan(channel: i, position: ch.pan)))
            out.append(OutboundMessage(key: "mute\(i)", bytes: Messages.mute(channel: i, on: ch.mute)))
            out.append(OutboundMessage(key: "phase\(i)", bytes: Messages.phase(channel: i, on: ch.phase)))
            for b in 0..<4 {
                out.append(OutboundMessage(key: "eq\(i).\(b)",
                                           bytes: Messages.eqBand(channel: i, band: b, ch.eq[b], enabled: ch.eqEnabled)))
            }
            out.append(OutboundMessage(key: "comp\(i)", bytes: Messages.compressor(channel: i, ch.comp)))
        }
        return out
    }
}

public struct OutboundMessage {
    public let key: String
    public let bytes: [UInt8]
    public init(key: String, bytes: [UInt8]) {
        self.key = key
        self.bytes = bytes
    }
}

/// Saves/loads the last-sent state. The hardware cannot be read back, so the
/// app remembers what it last told the device.
public enum StateStore {
    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("US16x08Panel", isDirectory: true).appendingPathComponent("state.json")
    }
    public static func load() -> MixerState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MixerState.self, from: data)
    }
    public static func save(_ state: MixerState) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
    }
}
