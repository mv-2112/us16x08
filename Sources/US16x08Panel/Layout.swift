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

import SwiftUI

/// Every size in the mixer comes from here, so the window minimum can never disagree with the strips.
enum Layout {
    static let outerPad: CGFloat = 12
    static let stripGap: CGFloat = 4
    static let stripMin: CGFloat = 48
    static let stripMax: CGFloat = 64
    static let masterWidth: CGFloat = 64
    static let masterGap: CGFloat = 10
    static let chipHeight: CGFloat = 18
    static let chipSpacing: CGFloat = 3
    static let captionHeight: CGFloat = 18
    static let dspHeight: CGFloat = 210
    static let faderMin: CGFloat = 90
    static let panHeight: CGFloat = 30

    /// Everything in a strip except the (flexible) fader.
    static let stripFixedHeight: CGFloat =
        14                                                   // channel number
        + 5 * chipHeight + 4 * chipSpacing                   // PHASE EQ COMP SOLO MUTE
        + panHeight + 14 + chipHeight                        // pan, dB readout, LINK
        + 6 * 4 + 10                                         // spacing + padding

    static let minWidth: CGFloat = 1000
    static let minHeight: CGFloat = dspHeight + 10 + captionHeight + 4 + stripFixedHeight + faderMin + 2 * outerPad
    static let defaultWidth: CGFloat = 1100
    static let defaultHeight: CGFloat = 650
}
