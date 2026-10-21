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
import US16x08Core

/// Shared plot geometry: a left margin for dB labels and a bottom margin for the frequency / input scale.
private struct PlotArea {
    static let left: CGFloat = 24
    static let bottom: CGFloat = 13
    static let top: CGFloat = 4
    static let right: CGFloat = 6
    let rect: CGRect
    init(_ size: CGSize) {
        rect = CGRect(x: PlotArea.left, y: PlotArea.top,
                      width: max(size.width - PlotArea.left - PlotArea.right, 10),
                      height: max(size.height - PlotArea.top - PlotArea.bottom, 10))
    }
}

private extension GraphicsContext {
    func label(_ s: String, at p: CGPoint, anchor: UnitPoint) {
        draw(Text(s).font(.system(size: 8)).foregroundColor(Color(white: 0.62)), at: p, anchor: anchor)
    }
}

// MARK: EQ response (log frequency, dB)

struct EQCurve: View {
    let bands: [EQBandSettings]
    let enabled: Bool
    /// (band, gain 0...24, frequency step)
    let onDrag: (Int, Int, Int) -> Void
    @State private var active: Int?

    static let minHz = 20.0
    static let maxHz = 20000.0
    static let rangeDB = 15.0
    static let gridHz: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    static let gridDB: [Double] = [-12, -6, 0, 6, 12]

    static func hzLabel(_ f: Double) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }

    private func xPos(_ hz: Double, _ r: CGRect) -> CGFloat {
        r.minX + CGFloat(log10(hz / EQCurve.minHz) / log10(EQCurve.maxHz / EQCurve.minHz)) * r.width
    }
    private func hzAt(_ x: CGFloat, _ r: CGRect) -> Double {
        EQCurve.minHz * pow(EQCurve.maxHz / EQCurve.minHz, Double((x - r.minX) / r.width))
    }
    private func yPos(_ db: Double, _ r: CGRect) -> CGFloat {
        r.midY - CGFloat(db / EQCurve.rangeDB) * r.height / 2
    }
    private func nodePoint(_ band: Int, _ r: CGRect) -> CGPoint {
        let b = bands[band]
        return CGPoint(x: xPos(EQTables.hz(band: band, step: b.frequency), r), y: yPos(Double(b.gain - 12), r))
    }

    var body: some View {
        GeometryReader { geo in
            let area = PlotArea(geo.size)
            Canvas { ctx, size in
                let r = area.rect
                // Grid: logarithmic frequency, linear dB.
                var grid = Path()
                for f in EQCurve.gridHz {
                    let x = xPos(f, r)
                    grid.move(to: CGPoint(x: x, y: r.minY)); grid.addLine(to: CGPoint(x: x, y: r.maxY))
                }
                for d in EQCurve.gridDB {
                    let y = yPos(d, r)
                    grid.move(to: CGPoint(x: r.minX, y: y)); grid.addLine(to: CGPoint(x: r.maxX, y: y))
                }
                ctx.stroke(grid, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                var zero = Path()
                zero.move(to: CGPoint(x: r.minX, y: yPos(0, r))); zero.addLine(to: CGPoint(x: r.maxX, y: yPos(0, r)))
                ctx.stroke(zero, with: .color(Color.white.opacity(0.3)), lineWidth: 1)

                // Scales
                let narrow = r.width < 220
                for f in EQCurve.gridHz {
                    if narrow && ![50, 100, 500, 1000, 5000, 10000].contains(f) { continue }
                    ctx.label(EQCurve.hzLabel(f), at: CGPoint(x: xPos(f, r), y: r.maxY + 2), anchor: .top)
                }
                for d in EQCurve.gridDB {
                    ctx.label(d > 0 ? "+\(Int(d))" : "\(Int(d))", at: CGPoint(x: r.minX - 3, y: yPos(d, r)), anchor: .trailing)
                }
                ctx.label("dB", at: CGPoint(x: 2, y: 1), anchor: .topLeading)

                // Response
                var curve = Path()
                let n = 160
                for i in 0...n {
                    let x = r.minX + r.width * CGFloat(i) / CGFloat(n)
                    let raw = EQResponse.magnitudeDB(bands: bands, atHz: hzAt(x, r))
                    let y = yPos(min(max(raw, -EQCurve.rangeDB), EQCurve.rangeDB), r)
                    if i == 0 { curve.move(to: CGPoint(x: x, y: y)) } else { curve.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(curve, with: .color(enabled ? Color.blue : Color.gray), lineWidth: 2.5)
                for b in 0..<4 {
                    let p = nodePoint(b, r)
                    let dot = Path(ellipseIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
                    ctx.fill(dot, with: .color(enabled ? Color.blue : Color.gray))
                    ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in handleDrag(v, area.rect) }
                    .onEnded { _ in active = nil }
            )
        }
        .background(Color(white: 0.07))
        .overlay(alignment: .topTrailing) { if !enabled { BypassLabel() } }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Drag a node: left/right = frequency, up/down = gain. Logarithmic frequency scale, ±12 dB.")
    }

    private func handleDrag(_ value: DragGesture.Value, _ r: CGRect) {
        if active == nil {
            var best = 0
            var bestDistance = CGFloat.infinity
            for b in 0..<4 {
                let p = nodePoint(b, r)
                let d = hypot(p.x - value.startLocation.x, p.y - value.startLocation.y)
                if d < bestDistance { bestDistance = d; best = b }
            }
            active = best
        }
        guard let b = active else { return }
        let x = min(max(value.location.x, r.minX), r.maxX)
        let step = clampInt(EQTables.step(band: b, nearestTo: hzAt(x, r)), EQBandSettings.frequencyRange(band: b))
        let dbValue = Double((r.midY - value.location.y) / (r.height / 2)) * EQCurve.rangeDB
        onDrag(b, clampInt(12 + Int(dbValue.rounded()), 0...24), step)
    }
}

// MARK: Compressor transfer curve (input dB vs output dB)

enum CompMath {
    static let span = 48.0

    static func ratio(_ index: Int) -> Double {
        let r = Messages.ratioTable[clampInt(index, 0...(Messages.ratioTable.count - 1))]
        return r == 0xff ? 100.0 : Double(r) / 10.0     // "∞:1" drawn as a hard limiter
    }

    /// Output level (dB) for an input level, including make-up gain. Hard knee.
    static func output(_ c: CompressorSettings, input: Double) -> Double {
        let thr = Double(c.thresholdDB)
        let o = input <= thr ? input : thr + (input - thr) / ratio(c.ratioIndex)
        return o + Double(c.gainDB)
    }

    /// Steady-state gain reduction for a 0 dBFS input.
    static func fullScaleReduction(_ c: CompressorSettings) -> Double {
        let thr = Double(c.thresholdDB)
        return (0 - thr) * (1 - 1 / ratio(c.ratioIndex))
    }
}

struct CompCurve: View {
    let comp: CompressorSettings
    let onThreshold: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let area = PlotArea(geo.size)
            Canvas { ctx, size in
                let r = area.rect
                let span = CompMath.span
                func pt(_ i: Double, _ o: Double) -> CGPoint {
                    CGPoint(x: r.minX + CGFloat((i + span) / span) * r.width,
                            y: r.maxY - CGFloat((o + span) / span) * r.height)
                }
                var grid = Path()
                for d in stride(from: -48.0, through: 0.0, by: 12.0) {
                    grid.move(to: pt(d, -span)); grid.addLine(to: pt(d, 0))
                    grid.move(to: pt(-span, d)); grid.addLine(to: pt(0, d))
                }
                ctx.stroke(grid, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                for d in stride(from: -48.0, through: 0.0, by: 12.0) {
                    ctx.label("\(Int(d))", at: CGPoint(x: pt(d, 0).x, y: r.maxY + 2), anchor: .top)
                    ctx.label("\(Int(d))", at: CGPoint(x: r.minX - 3, y: pt(0, d).y), anchor: .trailing)
                }
                ctx.label("out dB", at: CGPoint(x: 2, y: 1), anchor: .topLeading)
                ctx.label("in", at: CGPoint(x: r.maxX, y: r.maxY - 2), anchor: .bottomTrailing)

                var diag = Path()
                diag.move(to: pt(-span, -span)); diag.addLine(to: pt(0, 0))
                ctx.stroke(diag, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Transfer curve: threshold, ratio and make-up gain all move it. Clipped to the plot.
                var layer = ctx
                layer.clip(to: Path(r))
                let thr = Double(comp.thresholdDB)
                var line = Path()
                line.move(to: pt(-span, CompMath.output(comp, input: -span)))
                line.addLine(to: pt(thr, CompMath.output(comp, input: thr)))
                line.addLine(to: pt(0, CompMath.output(comp, input: 0)))
                let tint = comp.enabled ? Color.orange : Color.gray
                layer.stroke(line, with: .color(tint), lineWidth: 2.5)

                // Threshold handle on the knee.
                let p = pt(thr, CompMath.output(comp, input: thr))
                let dot = Path(ellipseIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
                layer.fill(dot, with: .color(tint))
                layer.stroke(dot, with: .color(.white), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let r = area.rect
                    let inDB = Double((v.location.x - r.minX) / r.width) * CompMath.span - CompMath.span
                    onThreshold(clampInt(Int(inDB.rounded()), CompressorSettings.thresholdRange))
                }
            )
        }
        .background(Color(white: 0.07))
        .overlay(alignment: .topTrailing) { if !comp.enabled { BypassLabel() } }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Input vs output level, −48…0 dB. Threshold, ratio and make-up gain reshape the curve; drag the node for the threshold.")
    }
}

// MARK: Compressor timing sketch

/// What attack and release do: a 0 dBFS burst pulls the gain down at the attack rate, then it recovers at the
/// release rate. A sketch of the idea (single-pole envelopes), not a measurement of the unit.
struct CompEnvelope: View {
    let comp: CompressorSettings

    var body: some View {
        Canvas { ctx, size in
            let attack = Double(comp.attackMS)
            let release = Double(comp.releaseMS)
            let depth = min(max(CompMath.fullScaleReduction(comp), 0), 24)
            let burst = max(attack * 3, 20)
            let total = burst + max(release * 3, 20)
            let r = CGRect(x: 2, y: 3, width: size.width - 4, height: size.height - 6)
            var base = Path()
            base.move(to: CGPoint(x: r.minX, y: r.minY)); base.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            ctx.stroke(base, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
            var path = Path()
            let n = 80
            for i in 0...n {
                let t = total * Double(i) / Double(n)
                let g = t <= burst ? depth * (1 - exp(-3 * t / max(attack, 1)))
                                   : depth * (1 - exp(-3 * burst / max(attack, 1))) * exp(-3 * (t - burst) / max(release, 1))
                let x = r.minX + r.width * CGFloat(t / total)
                let y = r.minY + r.height * CGFloat(g / 24)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(comp.enabled ? Color.orange : Color.gray), lineWidth: 1.5)
            ctx.draw(Text("A \(comp.attackMS) ms · R \(comp.releaseMS) ms").font(.system(size: 8)).foregroundColor(Color(white: 0.62)),
                     at: CGPoint(x: size.width - 3, y: size.height - 2), anchor: .bottomTrailing)
        }
        .background(Color(white: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Gain reduction over time for a loud burst: attack sets how fast it clamps down, release how fast it recovers.")
    }
}
