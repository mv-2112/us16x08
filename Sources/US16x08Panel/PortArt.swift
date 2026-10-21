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

/// Line drawings of the connectors on the unit, used on the Routing page.
enum PortKind: String {
    case xlr        // microphone inputs 1-8 (XLR / "canon")
    case jack       // 1/4" TRS line / instrument inputs and line outputs
    case usbB       // the USB-B socket the computer plugs into

    var caption: String {
        switch self {
        case .xlr: return "XLR"
        case .jack: return "¼″ jack"
        case .usbB: return "USB-B"
        }
    }
}

enum PortArt {
    /// Draws a port centred at `c`, roughly `size` points across.
    static func draw(_ kind: PortKind, in ctx: inout GraphicsContext, at c: CGPoint, size: CGFloat, color: Color = .secondary) {
        let lw = max(1, size / 18)
        func circle(_ r: CGFloat, at p: CGPoint, fill: Bool = false) {
            let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            if fill { ctx.fill(path, with: .color(color)) } else { ctx.stroke(path, with: .color(color), lineWidth: lw) }
        }
        let r = size / 2
        switch kind {
        case .xlr:
            circle(r, at: c)                                  // shell
            circle(r * 0.82, at: c)                           // inner wall
            // key slot at the top and latch notch at the bottom
            var key = Path()
            key.addRoundedRect(in: CGRect(x: c.x - r * 0.12, y: c.y - r * 0.98, width: r * 0.24, height: r * 0.3), cornerSize: CGSize(width: 1, height: 1))
            ctx.stroke(key, with: .color(color), lineWidth: lw)
            // three contact sockets in the XLR pattern
            let pins = [CGPoint(x: c.x - r * 0.32, y: c.y - r * 0.18),
                        CGPoint(x: c.x + r * 0.32, y: c.y - r * 0.18),
                        CGPoint(x: c.x, y: c.y + r * 0.38)]
            for p in pins { circle(r * 0.13, at: p, fill: true) }
        case .jack:
            circle(r, at: c)                                  // barrel
            circle(r * 0.72, at: c)
            circle(r * 0.42, at: c)                           // sleeve ring
            circle(r * 0.16, at: c, fill: true)               // tip contact
        case .usbB:
            // Squarish B socket with its two chamfered top corners.
            let w = size * 0.9, h = size * 0.9
            let x0 = c.x - w / 2, y0 = c.y - h / 2
            let ch = w * 0.22
            var outer = Path()
            outer.move(to: CGPoint(x: x0 + ch, y: y0))
            outer.addLine(to: CGPoint(x: x0 + w - ch, y: y0))
            outer.addLine(to: CGPoint(x: x0 + w, y: y0 + ch))
            outer.addLine(to: CGPoint(x: x0 + w, y: y0 + h))
            outer.addLine(to: CGPoint(x: x0, y: y0 + h))
            outer.addLine(to: CGPoint(x: x0, y: y0 + ch))
            outer.closeSubpath()
            ctx.stroke(outer, with: .color(color), lineWidth: lw)
            let inset = w * 0.16
            var inner = Path()
            inner.move(to: CGPoint(x: x0 + ch + inset * 0.3, y: y0 + inset))
            inner.addLine(to: CGPoint(x: x0 + w - ch - inset * 0.3, y: y0 + inset))
            inner.addLine(to: CGPoint(x: x0 + w - inset, y: y0 + ch + inset * 0.3))
            inner.addLine(to: CGPoint(x: x0 + w - inset, y: y0 + h - inset))
            inner.addLine(to: CGPoint(x: x0 + inset, y: y0 + h - inset))
            inner.addLine(to: CGPoint(x: x0 + inset, y: y0 + ch + inset * 0.3))
            inner.closeSubpath()
            ctx.stroke(inner, with: .color(color), lineWidth: lw)
            // the contact tongue
            let tongue = CGRect(x: c.x - w * 0.22, y: c.y - h * 0.02, width: w * 0.44, height: h * 0.14)
            ctx.fill(Path(roundedRect: tongue, cornerRadius: 1), with: .color(color))
        }
    }
}

/// Stand-alone view of a port drawing (used in tips and the Interface page).
struct PortIcon: View {
    let kind: PortKind
    var size: CGFloat = 28

    var body: some View {
        Canvas { ctx, sz in
            PortArt.draw(kind, in: &ctx, at: CGPoint(x: sz.width / 2, y: sz.height / 2), size: min(sz.width, sz.height) - 2)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(kind.caption)
        .help(kind.caption)
    }
}
