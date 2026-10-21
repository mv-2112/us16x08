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

/// One meter's peak-hold line and latched clip flag.
public struct PeakMeter: Equatable {
    /// Held peak in raw meter units; stays for `MeterPeaks.holdSeconds`, then falls.
    public var peak = 0.0
    /// Latched when the raw level reaches `MeterPeaks.clipRaw`; cleared by the user.
    public var clipped = false
    fileprivate var heldUntil = 0.0
    public init() {}

    fileprivate mutating func update(raw: Int, now: Double, dt: Double) {
        let r = Double(raw)
        if r >= peak {
            peak = r
            heldUntil = now + MeterPeaks.holdSeconds
        } else if now > heldUntil {
            let fallen = peak * pow(10.0, -MeterPeaks.decayDBPerSecond * dt / 20.0)
            peak = fallen < 1 ? 0 : max(r, fallen)
        }
        if raw >= MeterPeaks.clipRaw { clipped = true }
    }
}

/// Peak-hold and clip state for the 16 inputs and the two master meters.
/// A clipping input read 32765 of 32767 on real hardware, so 32700 (about -0.02 dBFS) counts as clipping.
public struct MeterPeaks: Equatable {
    public static let clipRaw = 32700
    public static let holdSeconds = 1.5
    public static let decayDBPerSecond = 20.0

    public var input = [PeakMeter](repeating: PeakMeter(), count: US16x08.channelCount)
    public var master = [PeakMeter](repeating: PeakMeter(), count: 2)
    private var lastTime: Double?
    public init() {}

    /// `now` is any monotonic seconds clock.
    public mutating func update(_ levels: MeterLevels, now: Double) {
        let dt = min(max(now - (lastTime ?? now), 0), 0.5)
        lastTime = now
        for i in 0..<US16x08.channelCount { input[i].update(raw: levels.input[i], now: now, dt: dt) }
        for i in 0..<2 { master[i].update(raw: levels.master[i], now: now, dt: dt) }
    }

    public mutating func clearAll() { self = MeterPeaks() }
}
