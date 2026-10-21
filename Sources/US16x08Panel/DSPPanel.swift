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

/// Docked EQ + compressor for the selected channel.
struct DSPPanel: View {
    @EnvironmentObject var model: AppModel
    let index: Int

    var body: some View {
        let ch = model.state.channels[index]
        HStack(alignment: .top, spacing: 10) {
            EQCard(index: index, ch: ch).frame(maxWidth: .infinity)
            CompCard(index: index, ch: ch).frame(width: 360)
        }
        .padding(.horizontal, Layout.outerPad)
        .padding(.top, 10)
        .frame(height: Layout.dspHeight + 10)
        .disabled(model.state.bypass)
        .overlay(alignment: .center) {
            if model.state.bypass {
                Text("Bypass").font(.title3.weight(.semibold)).foregroundStyle(Color(red: 0.62, green: 0.56, blue: 1.0))
                    .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8)).allowsHitTesting(false)
            }
        }
        .help(model.state.bypass ? "Mixer True Bypass is on: EQ and compressor are skipped by the unit" : "")
    }
}

struct EQCard: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let ch: ChannelState

    private let rows: [(band: Int, name: String)] = [(3, "HIGH"), (2, "HIGH MID"), (1, "LOW MID"), (0, "LOW")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EQUALIZER · ANALOG \(index + 1)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Spacer()
                Toggle("On", isOn: Binding(get: { ch.eqEnabled }, set: { model.setEQEnabled(index, $0) }))
                    .toggleStyle(.switch).controlSize(.small)
                Menu("Channel") {
                    Button("Copy DSP") { model.copyDSP(index) }
                    Button("Paste DSP") { model.pasteDSP(index) }.disabled(!model.canPasteDSP)
                    Divider()
                    Button("Reset DSP") { model.resetDSP(index) }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            HStack(alignment: .top, spacing: 10) {
                EQCurve(bands: ch.eq, enabled: ch.eqEnabled) { band, gain, step in
                    model.updateEQ(index, band: band) { $0.gain = gain; $0.frequency = step }
                }
                .frame(minWidth: 170, maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.band) { row in bandRow(row.band, row.name) }
                }
            }
        }
        .card()
    }

    private func bandRow(_ b: Int, _ name: String) -> some View {
        let s = ch.eq[b]
        let hasQ = b == 1 || b == 2
        let cutActive = (b == 0 && ch.lowCutRestoreGain != nil) || (b == 3 && ch.highCutRestoreGain != nil)
        let fr = EQBandSettings.frequencyRange(band: b)
        let hz = EQTables.hz(band: b, step: s.frequency)
        return HStack(spacing: 6) {
            Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            KnobField(title: "GAIN", value: s.gain, range: 0...24, defaultValue: 12,
                      text: String(s.gain - 12), unit: "dB", tint: .blue,
                      onChange: { v in model.updateEQ(index, band: b) { $0.gain = v } },
                      onCommit: { t in
                          if let v = ValueParsing.integer(t) { model.updateEQ(index, band: b) { $0.gain = clampInt(v + 12, 0...24) } }
                      })
                .disabled(cutActive)
            KnobField(title: "FREQ", value: s.frequency, range: fr, defaultValue: EQBandSettings.defaults[b].frequency,
                      text: hz < 1000 ? String(format: "%.0f", hz) : String(format: "%.1f", hz / 1000),
                      unit: hz < 1000 ? "Hz" : "kHz", tint: .blue,
                      onChange: { v in model.updateEQ(index, band: b) { $0.frequency = v } },
                      onCommit: { t in
                          if let f = ValueParsing.frequencyHz(t) {
                              let step = clampInt(EQTables.step(band: b, nearestTo: f), fr)
                              model.updateEQ(index, band: b) { $0.frequency = step }
                          }
                      })
            if hasQ {
                KnobField(title: "Q", value: s.width, range: 0...6, defaultValue: 2,
                          text: EQTables.qLabel(s.width), unit: "", tint: .blue,
                          onChange: { v in model.updateEQ(index, band: b) { $0.width = v } },
                          onCommit: { t in
                              if let q = ValueParsing.qIndex(t) { model.updateEQ(index, band: b) { $0.width = q } }
                          })
            } else {
                Color.clear.frame(width: 28 + 3 + 40 + 2 + 20 + 8, height: 28)
            }
            if b == 0 {
                ChipToggle(title: "LCF", isOn: ch.lowCutRestoreGain != nil, tint: .blue,
                           help: "Low-cut filter: pins the LOW band at −12 dB, as the original panel does") {
                    model.setLowCut(index, $0)
                }.frame(width: 34)
            } else if b == 3 {
                ChipToggle(title: "HCF", isOn: ch.highCutRestoreGain != nil, tint: .blue,
                           help: "High-cut: pins the HIGH shelf at −12 dB (an addition; the original panel has no HCF)") {
                    model.setHighCut(index, $0)
                }.frame(width: 34)
            } else {
                Color.clear.frame(width: 34, height: Layout.chipHeight)
            }
        }
    }
}

struct CompCard: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let ch: ChannelState

    var body: some View {
        let c = ch.comp
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COMPRESSOR · ANALOG \(index + 1)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Toggle("On", isOn: Binding(get: { c.enabled }, set: { v in model.updateComp(index) { $0.enabled = v } }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 4) {
                    CompCurve(comp: c) { v in model.updateComp(index) { $0.thresholdDB = v } }
                        .frame(maxHeight: .infinity)
                    CompEnvelope(comp: c).frame(height: 34)
                }
                .frame(width: 128)
                LiveGR(store: model.meterStore, channel: index, active: model.metersOn)
                    .frame(width: 7)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 38)
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        KnobField(title: "THRESHOLD", value: c.thresholdDB, range: CompressorSettings.thresholdRange, defaultValue: 0,
                                  text: String(c.thresholdDB), unit: "dB", tint: .orange,
                                  onChange: { v in model.updateComp(index) { $0.thresholdDB = v } },
                                  onCommit: { t in
                                      if let v = ValueParsing.integer(t) {
                                          model.updateComp(index) { $0.thresholdDB = clampInt(v, CompressorSettings.thresholdRange) }
                                      }
                                  })
                        KnobField(title: "RATIO", value: c.ratioIndex, range: 0...(Messages.ratioTable.count - 1), defaultValue: 0,
                                  text: CompressorSettings.ratioLabel(c.ratioIndex).replacingOccurrences(of: ":1", with: ""),
                                  unit: ":1", tint: .orange,
                                  onChange: { v in model.updateComp(index) { $0.ratioIndex = v } },
                                  onCommit: { t in
                                      if let i = ValueParsing.ratioIndex(t) { model.updateComp(index) { $0.ratioIndex = i } }
                                  })
                    }
                    GridRow {
                        KnobField(title: "GAIN", value: c.gainDB, range: CompressorSettings.gainRange, defaultValue: 0,
                                  text: String(c.gainDB), unit: "dB", tint: .orange,
                                  onChange: { v in model.updateComp(index) { $0.gainDB = v } },
                                  onCommit: { t in
                                      if let v = ValueParsing.integer(t) {
                                          model.updateComp(index) { $0.gainDB = clampInt(v, CompressorSettings.gainRange) }
                                      }
                                  })
                        KnobField(title: "ATTACK", value: (c.attackMS - 2) / 2, range: 0...99, defaultValue: 0,
                                  text: String(c.attackMS), unit: "ms", tint: .orange,
                                  onChange: { v in model.updateComp(index) { $0.attackMS = 2 * v + 2 } },
                                  onCommit: { t in
                                      if let v = ValueParsing.integer(t) {
                                          model.updateComp(index) { $0.attackMS = 2 * clampInt((v - 2 + 1) / 2, 0...99) + 2 }
                                      }
                                  })
                    }
                    GridRow {
                        KnobField(title: "RELEASE", value: c.releaseSteps, range: 1...100, defaultValue: 1,
                                  text: String(c.releaseMS), unit: "ms", tint: .orange,
                                  onChange: { v in model.updateComp(index) { $0.releaseSteps = v } },
                                  onCommit: { t in
                                      if let v = ValueParsing.integer(t) {
                                          model.updateComp(index) { $0.releaseSteps = clampInt((v + 5) / 10, 1...100) }
                                      }
                                  })
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .card()
    }
}
