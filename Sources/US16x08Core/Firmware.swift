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

/// One `[tag, type, payload]` entry of the unit's message stream.
/// Types: 0/1 = no payload, 2 = u8, 3 = u16 (little-endian), 4 = u32 (LE), 5 = `[len, bytes…]`.
/// Layout taken from the original panel's `usmsg_put` / `usmsg_get`.
public struct TLVItem: Equatable {
    public let tag: UInt8
    public let type: UInt8
    public let value: [UInt8]
}

public enum TLV {
    /// Parses until a 0/0 terminator, truncation or an unknown type.
    public static func parse(_ bytes: [UInt8]) -> [TLVItem] {
        var items: [TLVItem] = []
        var i = 0
        while i + 2 <= bytes.count {
            let tag = bytes[i]
            let type = bytes[i + 1]
            if tag == 0 && type == 0 { break }
            var header = 2
            var length = 0
            switch type {
            case 0, 1: length = 0
            case 2: length = 1
            case 3: length = 2
            case 4: length = 4
            case 5:
                guard i + 3 <= bytes.count else { return items }
                length = Int(bytes[i + 2])
                header = 3
            default: return items
            }
            guard i + header + length <= bytes.count else { return items }
            items.append(TLVItem(tag: tag, type: type, value: Array(bytes[(i + header)..<(i + header + length)])))
            i += header + length
        }
        return items
    }
}

public struct FirmwareInfo: Equatable {
    /// Decimal x100: 200 means firmware 2.00 (confirmed against a real V2.00 unit).
    public var versionRaw: UInt16?
    public var buildRaw: UInt16?
    public var productName: String?
    public var buildDate: String?
    public var buildTime: String?
    public var readyTagSeen = false
    /// Last 64-byte frame read; kept so odd results can be inspected.
    public var lastFrame: [UInt8] = []
    public init() {}

    public var versionText: String? {
        versionRaw.map { String(format: "%d.%02d", Int($0) / 100, Int($0) % 100) }
    }

    /// Same format as the original panel: "2.00 0022" (version, then build padded to 4 digits).
    public var displayText: String? {
        guard let v = versionText else { return nil }
        guard let b = buildRaw else { return v }
        return v + " " + String(format: "%04d", Int(b))
    }

    /// e.g. "2.00 0022 · Aug 22 2016 11:03:18"
    public var summary: String? {
        guard let d = displayText else { return nil }
        let stamp = [buildDate, buildTime].compactMap { $0 }.joined(separator: " ")
        return stamp.isEmpty ? d : d + " · " + stamp
    }
}

public enum Firmware {
    public static func extract(from frame: [UInt8], into info: inout FirmwareInfo) {
        for item in TLV.parse(frame) {
            if item.type == 3 && item.value.count == 2 {
                let v = UInt16(item.value[0]) | (UInt16(item.value[1]) << 8)
                if item.tag == 0x32 { info.versionRaw = v }
                if item.tag == 0x33 { info.buildRaw = v }
            } else if item.type == 5 {
                let text = String(decoding: item.value, as: UTF8.self)
                if item.tag == 0x34 { info.productName = text }
                if item.tag == 0x35 { info.buildDate = text }
                if item.tag == 0x36 { info.buildTime = text }
            }
        }
    }
}
