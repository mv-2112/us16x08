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
import AppKit
import US16x08Core

/// Signal-flow diagram adapted from the original "Output Setting" tab.
/// Lines to each Line Out follow the currently selected source.
struct RoutingScreen: View {
    @EnvironmentObject var model: AppModel

    private let green = Color.green
    private let violet = Color(red: 0.56, green: 0.48, blue: 1.0)

    private func busX(_ source: Int) -> CGFloat {
        source < 2 ? 460 + CGFloat(source) * 28 : 560 + CGFloat(source - 2) * 22
    }
    private func rowY(_ out: Int) -> CGFloat { 60 + CGFloat(out) * 66 }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawDiagram(&ctx) }
                    .frame(width: 1060, height: 600)
                ForEach(0..<US16x08.outputCount, id: \.self) { out in
                    HStack {
                        Text("Line Out \(out + 1)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(get: { model.state.routes[out] },
                                                      set: { model.setRoute(out, $0) })) {
                            ForEach(0..<Messages.routeSourceNames.count, id: \.self) { i in
                                Text(Messages.routeSourceNames[i]).tag(i)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 240, height: 44)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
                    .position(x: 890, y: rowY(out) + 22)
                }
                Toggle("Computer out → Stereo Bus", isOn: Binding(get: { model.state.bussOut },
                                                                 set: { model.setBussOut($0) }))
                    .toggleStyle(.switch)
                    .disabled(!model.connected)
                    .frame(width: 250)
                    .position(x: 330, y: 560)
                    .help("Computer playback (odd → L, even → R) feeds the mixer's stereo bus. OFF selectable since v2.10.")
            }
            .frame(width: 1060, height: 600)
            .padding(20)
            Text("Each Line Out (a ¼″ jack on the back) chooses Master L, Master R or Computer 1–8. Phones and Line Out 1–2 level: to be confirmed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func drawText(_ ctx: inout GraphicsContext, _ s: String, _ p: CGPoint,
                          size: CGFloat = 12, weight: Font.Weight = .regular, color: Color = .secondary) {
        ctx.draw(Text(s).font(.system(size: size, weight: weight)).foregroundColor(color), at: p, anchor: .leading)
    }

    private func drawCard(_ ctx: inout GraphicsContext, _ rect: CGRect, _ title: String, _ rows: [String]) {
        let shape = Path(roundedRect: rect, cornerRadius: 14)
        ctx.fill(shape, with: .color(Color(nsColor: .controlBackgroundColor)))
        ctx.stroke(shape, with: .color(Color.secondary.opacity(0.3)), lineWidth: 1)
        drawText(&ctx, title, CGPoint(x: rect.minX + 14, y: rect.minY + 24), size: 14, weight: .semibold, color: .primary)
        for (i, r) in rows.enumerated() {
            drawText(&ctx, r, CGPoint(x: rect.minX + 14, y: rect.minY + 54 + CGFloat(i) * 24))
        }
    }

    private func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(color), lineWidth: width)
    }

    private func dot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(color))
    }

    private func drawDiagram(_ ctx: inout GraphicsContext) {
        let grey = Color.secondary.opacity(0.6)

        drawCard(&ctx, CGRect(x: 10, y: 40, width: 190, height: 150), "Analog Input",
                 ["Mic 1–8", "Line / Inst 9–10", "Line 11–16"])
        // The connector for each input group, drawn at the right edge of the card.
        PortArt.draw(.xlr, in: &ctx, at: CGPoint(x: 172, y: 40 + 54), size: 24)
        PortArt.draw(.jack, in: &ctx, at: CGPoint(x: 172, y: 40 + 78), size: 20)
        PortArt.draw(.jack, in: &ctx, at: CGPoint(x: 172, y: 40 + 102), size: 20)
        drawText(&ctx, "XLR · mic inputs on the front", CGPoint(x: 14, y: 40 + 128), size: 9)
        drawCard(&ctx, CGRect(x: 250, y: 40, width: 130, height: 150), "Mixer",
                 ["16 channels", "EQ · Comp", "Fader · Pan"])
        drawCard(&ctx, CGRect(x: 10, y: 400, width: 190, height: 110), "From Computer",
                 ["DAW playback"])
        PortArt.draw(.usbB, in: &ctx, at: CGPoint(x: 160, y: 400 + 66), size: 40)
        drawText(&ctx, "USB-B", CGPoint(x: 14, y: 400 + 94), size: 9)

        line(&ctx, CGPoint(x: 200, y: 115), CGPoint(x: 250, y: 115), grey, 2)
        line(&ctx, CGPoint(x: 380, y: 115), CGPoint(x: 460, y: 115), grey, 2)

        // Buses (dimmed; the ones in use are highlighted by their connector below)
        drawText(&ctx, "Stereo Bus", CGPoint(x: 452, y: 24), weight: .semibold, color: green)
        drawText(&ctx, "L", CGPoint(x: 456, y: 48), size: 11, color: green)
        drawText(&ctx, "R", CGPoint(x: 484, y: 48), size: 11, color: green)
        for i in 0..<2 {
            line(&ctx, CGPoint(x: busX(i), y: 60), CGPoint(x: busX(i), y: 560), green.opacity(0.55), 4)
            dot(&ctx, CGPoint(x: busX(i), y: 115), green)
        }
        drawText(&ctx, "Computer Bus 1–8", CGPoint(x: 556, y: 24), weight: .semibold, color: violet)
        for i in 0..<8 {
            let x = busX(i + 2)
            drawText(&ctx, "\(i + 1)", CGPoint(x: x - 3, y: 48), size: 11, color: violet)
            line(&ctx, CGPoint(x: x, y: 60), CGPoint(x: x, y: 560), violet.opacity(0.55), 4)
        }

        // Computer playback feeding the computer bus
        line(&ctx, CGPoint(x: 200, y: 440), CGPoint(x: 560, y: 440), violet, 2.5)
        line(&ctx, CGPoint(x: 200, y: 490), CGPoint(x: 582, y: 490), violet, 2.5)
        drawText(&ctx, "Computer – odd", CGPoint(x: 214, y: 430), size: 11)
        drawText(&ctx, "Computer – even", CGPoint(x: 214, y: 480), size: 11)

        // Computer out → Stereo Bus junctions (odd → L, even → R)
        if model.state.bussOut {
            dot(&ctx, CGPoint(x: busX(0), y: 440), green)
            dot(&ctx, CGPoint(x: busX(1), y: 490), green)
        }

        // Current routing: one connector per Line Out
        let routes = model.state.routes
        for out in 0..<US16x08.outputCount {
            let src = routes[out]
            let color = src < 2 ? green : violet
            let y = rowY(out) + 22
            line(&ctx, CGPoint(x: busX(src), y: y), CGPoint(x: 770, y: y), color, 2.5)
            dot(&ctx, CGPoint(x: busX(src), y: y), color)
            PortArt.draw(.jack, in: &ctx, at: CGPoint(x: 1034, y: y), size: 26)
        }
    }
}
