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
import CUSB

/// Reports USB plug/unplug of the US-16x08 on the main run loop.
public final class DeviceWatcher {
    private var handle: OpaquePointer?
    private let onChange: (Bool) -> Void

    /// `onChange(true)` = plugged in, `onChange(false)` = removed.
    public init(vendorID: UInt16 = US16x08.vendorID, productID: UInt16 = US16x08.productID,
                onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        handle = cusb_watch_start(vendorID, productID, { attached, ctx in
            guard let ctx = ctx else { return }
            Unmanaged<DeviceWatcher>.fromOpaque(ctx).takeUnretainedValue().onChange(attached != 0)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { if let h = handle { cusb_watch_stop(h) } }
}
