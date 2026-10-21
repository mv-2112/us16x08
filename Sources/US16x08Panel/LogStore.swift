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

/// Rolling diagnostic log. Appending is thread-safe and cheap; SwiftUI is told at most four times a
/// second, and only the Diagnostics window observes this, so USB traffic can never make the main
/// window re-render.
final class LogStore: ObservableObject {
    @Published private(set) var revision = 0
    private let lock = NSLock()
    private var lines: [String] = []
    private var pending = false
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func append(_ text: String) {
        LogStore.stampLock.lock()
        let stamp = LogStore.stamp.string(from: Date())
        LogStore.stampLock.unlock()
        let line = stamp + "  " + text
        lock.lock()
        lines.append(line)
        if lines.count > 1000 { lines.removeFirst(lines.count - 1000) }
        let schedule = !pending
        pending = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.pending = false
                self.lock.unlock()
                self.revision += 1
            }
        }
    }

    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.revision += 1 }
    }

    // DateFormatter is not thread-safe; guard it.
    private static let stampLock = NSLock()
}
