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

/// Latest meter levels plus peak/clip state, written from the link queue and read by the UI.
///
/// Deliberately NOT an ObservableObject: publishing every meter tick through the app model made
/// SwiftUI rebuild the whole window (menus, toolbar, DSP panel) dozens of times a second.
/// Meter views poll this store on their own timer instead.
public final class MeterStore {
    private let lock = NSLock()
    private var levels = MeterLevels()
    private var peaks = MeterPeaks()

    public init() {}

    public func update(_ new: MeterLevels, now: Double) {
        lock.lock()
        levels = new
        peaks.update(new, now: now)
        lock.unlock()
    }

    public func input(_ ch: Int) -> (level: Int, peak: Double, clipped: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard ch >= 0 && ch < levels.input.count else { return (0, 0, false) }
        return (levels.input[ch], peaks.input[ch].peak, peaks.input[ch].clipped)
    }

    public func master(_ side: Int) -> (level: Int, peak: Double, clipped: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard side >= 0 && side < 2 else { return (0, 0, false) }
        return (levels.master[side], peaks.master[side].peak, peaks.master[side].clipped)
    }

    public func compReduction(_ ch: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard ch >= 0 && ch < levels.compReduction.count else { return 0 }
        return levels.compReduction[ch]
    }

    public func clearClip(input ch: Int) {
        lock.lock(); defer { lock.unlock() }
        if ch >= 0 && ch < peaks.input.count { peaks.input[ch].clipped = false }
    }

    public func clearClip(master side: Int) {
        lock.lock(); defer { lock.unlock() }
        if side >= 0 && side < 2 { peaks.master[side].clipped = false }
    }

    public func clearPeaks() { lock.lock(); peaks.clearAll(); lock.unlock() }

    public func reset() {
        lock.lock()
        levels = MeterLevels()
        peaks.clearAll()
        lock.unlock()
    }
}
