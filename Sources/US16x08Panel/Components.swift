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

func clampInt(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
func faderLabel(_ db: Int) -> String { db <= -61 ? "-inf" : (db > 0 ? "+\(db)" : "\(db)") }

extension View {
    /// Opaque content surface. Glass is left to the system chrome (toolbar).
    func card() -> some View {
        self.padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
    }
}

struct BypassLabel: View {
    var body: some View {
        Text("Bypass")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(red: 0.62, green: 0.56, blue: 1.0))
            .padding(6)
            .allowsHitTesting(false)
    }
}

// MARK: Chips

/// Tinted full-width chip button (PHASE, EQ, COMP, SOLO, MUTE, LINK ...).
struct ChipToggle: View {
    let title: String
    let isOn: Bool
    var tint: Color = .accentColor
    var help: String = ""
    let action: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button { action(!isOn) } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.chipHeight)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? tint : Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: Knob and number box

/// Rotary control: drag up/down, double-click to reset. Values are integer steps.
struct Knob: View {
    let value: Int
    let range: ClosedRange<Int>
    let defaultValue: Int
    var size: CGFloat = 28
    var tint: Color = .accentColor
    var bipolar = false
    let onChange: (Int) -> Void
    @State private var dragStart: Int?
    @Environment(\.isEnabled) private var enabled

    private var span: Double { Double(max(range.upperBound - range.lowerBound, 1)) }
    private var fraction: Double { Double(value - range.lowerBound) / span }

    /// Angle in degrees from 12 o'clock, clockwise.
    private func angle(_ f: Double) -> Double { -135 + 270 * f }

    private func point(_ c: CGPoint, _ r: CGFloat, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
    }

    private func arc(_ c: CGPoint, _ r: CGFloat, from a: Double, to b: Double) -> Path {
        var p = Path()
        let steps = max(2, Int(abs(b - a) / 4))
        for i in 0...steps {
            let pt = point(c, r, a + (b - a) * Double(i) / Double(steps))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2 - 2
            ctx.stroke(arc(c, r, from: -135, to: 135), with: .color(Color.secondary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let from = bipolar ? 0.0 : -135.0
            let to = angle(fraction)
            if abs(to - from) > 0.5 {
                ctx.stroke(arc(c, r, from: from, to: to), with: .color(tint),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            let body = Path(ellipseIn: CGRect(x: c.x - r + 4, y: c.y - r + 4, width: 2 * (r - 4), height: 2 * (r - 4)))
            ctx.fill(body, with: .color(Color(white: 0.22)))
            var needle = Path()
            needle.move(to: point(c, r - 8, to))
            needle.addLine(to: point(c, r - 3, to))
            ctx.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: size, height: size)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    let start = dragStart ?? value
                    dragStart = start
                    let delta = Int((-v.translation.height / 140 * span).rounded())
                    let n = clampInt(start + delta, range)
                    if n != value { onChange(n) }
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { if enabled { onChange(defaultValue) } })
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onChange(clampInt(value + 1, range))
            case .decrement: onChange(clampInt(value - 1, range))
            @unknown default: break
            }
        }
    }
}

/// Black read-out you can also type into. Enter applies (the caller snaps to the nearest legal step); leaving the field cancels.
struct NumberBox: View {
    let text: String
    var width: CGFloat = 40
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(red: 0.85, green: 0.95, blue: 0.85))
            .padding(.horizontal, 4)
            .frame(width: width, height: 18)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 4))
            .opacity(enabled ? 1 : 0.4)
            .onAppear { draft = text }
            .onChange(of: text) { _, new in if !focused { draft = new } }
            .onChange(of: focused) { _, f in if !f { draft = text } }
            .onSubmit {
                commit(draft)
                focused = false
                draft = text
            }
    }
}

/// Knob + title + number box + unit, the building block of the EQ and compressor panels.
struct KnobField: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let defaultValue: Int
    let text: String
    let unit: String
    var tint: Color = .accentColor
    let onChange: (Int) -> Void
    let onCommit: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            Knob(value: value, range: range, defaultValue: defaultValue, tint: tint, onChange: onChange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    NumberBox(text: text, commit: onCommit)
                    Text(unit).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                }
            }
        }
        .help("\(title): drag the knob, double-click to reset, or type a value")
    }
}

// MARK: Pan, fader

struct PanKnob: View {
    let pos: Int
    let onChange: (Int) -> Void

    private var tip: String {
        if pos == 0 { return "Pan: centre" }
        let pct = Int((Double(abs(pos)) / 127.0 * 100).rounded())
        return "Pan: \(pos < 0 ? "L" : "R")\(pct)"
    }

    var body: some View {
        Knob(value: pos, range: -127...127, defaultValue: 0, size: Layout.panHeight, tint: .secondary, bipolar: true, onChange: onChange)
            .help(tip + " (double-click to centre)")
    }
}

/// Console-style fader with a dB scale and a metal cap; 0 dB sits at about 80% of the travel.
struct Fader: View {
    let db: Int
    let onChange: (Int) -> Void
    @Environment(\.isEnabled) private var enabled
    private let capH: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let travel = max(h - capH, 1)
            let y = capH / 2 + travel * CGFloat(1 - FaderTaper.position(db: db))
            Canvas { ctx, sz in
                let cx = sz.width / 2
                ctx.fill(Path(roundedRect: CGRect(x: cx - 2, y: capH / 2, width: 4, height: travel), cornerRadius: 2),
                         with: .color(Color.black.opacity(0.75)))
                for t in FaderTaper.tickDBs {
                    let ty = capH / 2 + travel * CGFloat(1 - FaderTaper.position(db: t))
                    var p = Path()
                    p.move(to: CGPoint(x: 1, y: ty)); p.addLine(to: CGPoint(x: 5, y: ty))
                    p.move(to: CGPoint(x: sz.width - 5, y: ty)); p.addLine(to: CGPoint(x: sz.width - 1, y: ty))
                    ctx.stroke(p, with: .color(Color.secondary.opacity(t == 0 ? 0.9 : 0.5)), lineWidth: t == 0 ? 1.5 : 1)
                }
                let cap = CGRect(x: cx - 10, y: y - capH / 2, width: 20, height: capH)
                ctx.fill(Path(roundedRect: cap, cornerRadius: 3),
                         with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]),
                                               startPoint: CGPoint(x: 0, y: cap.minY), endPoint: CGPoint(x: 0, y: cap.maxY)))
                ctx.stroke(Path(roundedRect: cap, cornerRadius: 3), with: .color(Color.black.opacity(0.5)), lineWidth: 0.5)
                var line = Path()
                line.move(to: CGPoint(x: cap.minX + 2, y: y)); line.addLine(to: CGPoint(x: cap.maxX - 2, y: y))
                ctx.stroke(line, with: .color(Color.black.opacity(0.7)), lineWidth: 1.5)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2).onChanged { v in
                    let pos = 1 - Double((v.location.y - capH / 2) / travel)
                    let n = FaderTaper.db(position: pos)
                    if n != db { onChange(n) }
                }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { if enabled { onChange(0) } })
        }
        .opacity(enabled ? 1 : 0.5)
        .help("Double-click for 0 dB")
        .accessibilityElement()
        .accessibilityLabel("Fader")
        .accessibilityValue(db <= -61 ? "minus infinity" : "\(db) dB")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onChange(min(db <= -61 ? -60 : db + 1, 6))
            case .decrement: onChange(db <= -60 ? -127 : db - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: Meters

/// Segmented LED ladder, -48...0 dBFS in 2 dB steps. Green to -12, yellow -12...-6, red above, peak-hold segment,
/// clip LED on top. Click anywhere on it to clear the clip LED.
struct LEDLadder: View {
    let level: Int
    var peak: Double = 0
    var clipped = false
    var onClear: (() -> Void)? = nil

    static let floorDB = -48.0
    static let stepDB = 2.0
    static let segments = 24

    static func color(topDB: Double) -> Color {
        if topDB <= -12 { return .green }
        if topDB <= -6 { return .yellow }
        return .red
    }

    private var helpText: String {
        guard let p = MeterScale.dBFS(Int(peak)) else { return "Peak: –  (click to clear)" }
        return String(format: "Peak %.1f dBFS%@  (click to clear)", p, clipped ? " · CLIPPED" : "")
    }

    var body: some View {
        Canvas { ctx, sz in
            let clipH: CGFloat = 5
            let top = clipH + 2
            let n = LEDLadder.segments
            let gap: CGFloat = 1
            let segH = (sz.height - top - gap * CGFloat(n - 1)) / CGFloat(n)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: sz.width, height: clipH), cornerRadius: 1.5),
                     with: .color(clipped ? Color.red : Color.red.opacity(0.2)))
            let lvl = MeterScale.dBFS(level) ?? -200
            let pk = MeterScale.dBFS(Int(peak)) ?? -200
            let peakIndex = pk > LEDLadder.floorDB ? min(n - 1, Int(((pk - LEDLadder.floorDB) / LEDLadder.stepDB).rounded(.down))) : -1
            for i in 0..<n {
                let topDB = LEDLadder.floorDB + LEDLadder.stepDB * Double(i + 1)
                let y = sz.height - CGFloat(i + 1) * segH - CGFloat(i) * gap
                let col = LEDLadder.color(topDB: topDB)
                let lit = lvl > topDB - LEDLadder.stepDB
                let isPeak = i == peakIndex
                let r = CGRect(x: 0, y: y, width: sz.width, height: segH)
                ctx.fill(Path(r), with: .color(col.opacity(lit || isPeak ? 1 : 0.17)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClear?() }
        .help(helpText)
        .accessibilityLabel(clipped ? "Level meter, clipped" : "Level meter")
    }
}

/// Gain-reduction bar, 0...24 dB, growing downward.
struct GRBar: View {
    let level: Int

    var body: some View {
        GeometryReader { g in
            let f = min(max(MeterScale.reductionDB(level) / 24.0, 0), 1)
            ZStack(alignment: .top) {
                Rectangle().fill(Color.black.opacity(0.6))
                Rectangle().fill(Color.orange).frame(height: g.size.height * CGFloat(f))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help("Gain reduction, 0–24 dB")
    }
}

struct LiveMeter: View {
    enum Source {
        case input(Int)
        case master(Int)
    }
    let store: MeterStore
    let source: Source
    let active: Bool

    private func reading() -> (level: Int, peak: Double, clipped: Bool) {
        switch source {
        case .input(let ch): return store.input(ch)
        case .master(let side): return store.master(side)
        }
    }
    private func clear() {
        switch source {
        case .input(let ch): store.clearClip(input: ch)
        case .master(let side): store.clearClip(master: side)
        }
    }

    var body: some View {
        // ~30 fps while connected; idle ticks once a second so a reset still shows.
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0)) { _ in
            let r = reading()
            LEDLadder(level: r.level, peak: r.peak, clipped: r.clipped, onClear: clear)
        }
    }
}

struct LiveGR: View {
    let store: MeterStore
    let channel: Int
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 30.0 : 1.0)) { _ in
            GRBar(level: store.compReduction(channel))
        }
    }
}
